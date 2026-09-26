import Foundation
import Observation
import SwiftData
import UserNotifications

/// Prepares editions for each slot (up to an hour ahead), makes them ready on time, enforces
/// "never pile up", and keeps notifications in step with the schedule (SPEC › Scheduling and delivery).
@MainActor @Observable
final class EditionScheduler {
    private let library: LibraryStore
    private let ai: AIService
    private var context: ModelContext { library.context }
    /// Bumped on every change so views that read editions refresh.
    private(set) var version = 0
    private var generatingBrief = false
    /// The last pipeline run produced nothing; fall back to a passage until a topic or setting changes.
    var briefFailed = false

    init(library: LibraryStore, ai: AIService) {
        self.library = library
        self.ai = ai
    }

    // MARK: Queries

    func editions(on day: Date, calendar: Calendar = .current) -> [Edition] {
        let start = calendar.startOfDay(for: day)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? day
        let d = FetchDescriptor<Edition>(predicate: #Predicate { $0.scheduledFor >= start && $0.scheduledFor < end },
                                         sortBy: [SortDescriptor(\.scheduledFor)])
        return (try? context.fetch(d)) ?? []
    }

    /// The newest ready edition nobody has read yet (menu bar dot, Today).
    func readyUnread(now: Date = .now) -> Edition? {
        let ready = EditionState.ready.rawValue
        let d = FetchDescriptor<Edition>(predicate: #Predicate { $0.stateRaw == ready }, sortBy: [SortDescriptor(\.scheduledFor, order: .reverse)])
        return (try? context.fetch(d))?.first { $0.scheduledFor <= now }
    }

    func edition(for occurrence: SlotOccurrence, kind: EditionKind) -> Edition? {
        editions(on: occurrence.date).first { $0.slotID == occurrence.slot.id && $0.kind == kind }
    }

    /// Signals that library content changed outside the scheduler (imports, samples).
    func touch() { version += 1 }

    // MARK: Refresh

    /// Call on launch, every half-minute, and whenever the schedule or library changes.
    func refresh(prefs: Preferences, now: Date = .now) {
        guard !prefs.isPaused(at: now) else { return }
        var changed = false
        for occurrence in SchedulePlanner.due(at: now, slots: prefs.slots) {
            for kind in kinds(for: occurrence.slot.content) {
                if let existing = edition(for: occurrence, kind: kind) {
                    changed = repair(existing) || changed
                } else if let created = prepare(occurrence, kind: kind) {
                    context.insert(created)
                    changed = true
                }
            }
        }
        // Prepared → ready at slot time.
        let prepared = EditionState.prepared.rawValue
        let pending = (try? context.fetch(FetchDescriptor<Edition>(predicate: #Predicate { $0.stateRaw == prepared }))) ?? []
        var newestReady: Date?
        for e in pending where e.scheduledFor <= now {
            e.state = .ready
            newestReady = max(newestReady ?? e.scheduledFor, e.scheduledFor)
            changed = true
        }
        if prefs.neverPileUp, let newest = newestReady ?? readyUnread(now: now)?.scheduledFor {
            changed = replaceOlder(than: newest) || changed
        }
        if changed {
            library.save()
            version += 1
        }
    }

    private func kinds(for content: SlotContent) -> [EditionKind] {
        switch content {
        case .passage, .publication: [.passage] // Feeds aren't supported yet; publications fall back to the serial.
        case .brief: [.brief]
        case .passageAndBrief: [.passage, .brief]
        }
    }

    private func prepare(_ occurrence: SlotOccurrence, kind: EditionKind) -> Edition? {
        switch kind {
        case .passage:
            guard let part = nextPart() else { return nil }
            return Edition(slotID: occurrence.slot.id, scheduledFor: occurrence.date, kind: .passage, part: part)
        case .brief:
            if let brief = unreadBrief() {
                return Edition(slotID: occurrence.slot.id, scheduledFor: occurrence.date, kind: .brief, brief: brief)
            }
            if ai.isEnabled(.brief), !briefFailed {
                generateBriefInBackground() // The next refresh picks the new Brief up.
                return nil
            }
            // No Brief (AI off, or no sources): deliver a passage instead.
            return nextPart().map { Edition(slotID: occurrence.slot.id, scheduledFor: occurrence.date, kind: .passage, part: $0) }
        }
    }

    /// A prepared passage whose part vanished (re-chunked) gets the current next part.
    private func repair(_ edition: Edition) -> Bool {
        guard edition.kind == .passage, edition.part == nil, edition.state != .read else { return false }
        edition.part = nextPart()
        return true
    }

    private func nextPart() -> Part? {
        guard let work = library.currentWork else { return nil }
        if let part = work.nextPart { return part }
        work.status = .finished
        return library.currentWork?.nextPart
    }

    private func unreadBrief() -> Brief? {
        let d = FetchDescriptor<Brief>(predicate: #Predicate { $0.readAt == nil }, sortBy: [SortDescriptor(\.createdAt)])
        let used = Set(((try? context.fetch(FetchDescriptor<Edition>())) ?? []).compactMap { $0.brief?.id })
        return ((try? context.fetch(d)) ?? []).first { !used.contains($0.id) }
    }

    /// Unread editions from earlier slots become `replaced`; their part simply stays next in line.
    private func replaceOlder(than newest: Date) -> Bool {
        let all = (try? context.fetch(FetchDescriptor<Edition>())) ?? []
        let ids = Set(SchedulePlanner.toReplace(all.map { ($0.id, $0.scheduledFor, $0.state) }, newestReady: newest))
        for e in all where ids.contains(e.id) { e.state = .replaced }
        return !ids.isEmpty
    }

    // MARK: Reading

    /// Finishing a passage advances the serial.
    func finish(part: Part, edition: Edition?) {
        part.readAt = .now
        if let work = part.work, work.nextPartIndex <= part.index {
            work.nextPartIndex = part.index + 1
            if work.nextPart == nil { work.status = .finished }
        }
        edition?.state = .read
        library.save()
        version += 1
    }

    func finish(brief: Brief, edition: Edition?) {
        brief.readAt = .now
        edition?.state = .read
        library.save()
        version += 1
    }

    // MARK: The Brief

    /// Runs the pipeline for the best-weighted active topic and stores the result.
    func generateBriefInBackground() {
        guard !generatingBrief, ai.isEnabled(.brief) else { return }
        let topics = library.topics().filter { $0.isActive && $0.weight > 0.2 }
        guard let topic = Self.pickTopic(topics) else { return }
        generatingBrief = true
        let label = topic.label, past = topic.pastAngles, deeper = topic.deeperAngle
        Task {
            defer { generatingBrief = false }
            guard let provider = await ai.availableProvider(for: .brief),
                  let draft = try? await BriefPipeline.run(topic: label, pastAngles: past, deeper: deeper, provider: provider) else {
                briefFailed = true
                return
            }
            topic.pastAngles.append(draft.angle)
            topic.deeperAngle = nil
            context.insert(Brief(topicLabel: label, title: draft.title, standfirst: draft.standfirst, body: draft.body, sources: draft.sources))
            library.save()
            version += 1
        }
    }

    /// Weighted, deterministic pick: the topic with the highest weight whose last Brief is oldest.
    static func pickTopic(_ topics: [Topic]) -> Topic? {
        topics.max { a, b in
            if a.weight != b.weight { return a.weight < b.weight }
            return a.pastAngles.count > b.pastAngles.count
        }
    }

    // MARK: Notifications

    func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    /// One repeating notification per slot and weekday. Quiet arrival: none (only the menu bar dot).
    func scheduleNotifications(prefs: Preferences) {
        let center = UNUserNotificationCenter.current()
        center.removeAllPendingNotificationRequests()
        guard !prefs.quietArrival else { return }
        for slot in prefs.slots {
            let content = UNMutableNotificationContent()
            content.title = "Your \(slot.editionName.lowercased()) is ready"
            content.body = slot.content == .brief ? "The Brief, a few minutes long." : "A few minutes of reading, waiting for you."
            content.sound = .default
            for weekday in slot.weekdays {
                var components = DateComponents()
                components.hour = slot.hour
                components.minute = slot.minute
                if slot.weekdays != ScheduleSlot.everyDay { components.weekday = weekday }
                let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
                center.add(UNNotificationRequest(identifier: "slot-\(slot.id)-\(weekday)", content: content, trigger: trigger))
                if slot.weekdays == ScheduleSlot.everyDay { break }
            }
        }
    }
}
