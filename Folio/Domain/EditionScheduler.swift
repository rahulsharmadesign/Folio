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
    private var generating: BriefKind?
    /// Kinds whose last pipeline run produced nothing, and when; retried after `retryAfter`
    /// or when topics, quotes or feeds change.
    private var failedAt: [BriefKind: Date] = [:]
    static let retryAfter: TimeInterval = 30 * 60

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

    func edition(for occurrence: SlotOccurrence) -> Edition? {
        editions(on: occurrence.date).first { $0.slotID == occurrence.slot.id && $0.kind == .brief }
    }

    /// The kind of Brief a delivery brings; "Your topics" needs an active topic, else it's a story.
    func briefKind(for occurrence: SlotOccurrence) -> BriefKind {
        let kind = occurrence.slot.content.briefKind(on: occurrence.date, hour: occurrence.slot.hour)
        if kind == .topic, !library.topics().contains(where: { $0.isActive && $0.weight > 0.2 }) { return .story }
        return kind
    }

    /// An unread Brief of this kind that no edition has used yet: what the next delivery of it will be.
    func unreadBrief(of kind: BriefKind) -> Brief? {
        let d = FetchDescriptor<Brief>(predicate: #Predicate { $0.readAt == nil }, sortBy: [SortDescriptor(\.createdAt)])
        let used = Set(((try? context.fetch(FetchDescriptor<Edition>())) ?? []).compactMap { $0.brief?.id })
        return ((try? context.fetch(d)) ?? []).first { $0.kind == kind && !used.contains($0.id) }
    }

    /// Topics, quotes or feeds changed: try every kind again.
    func retryBriefs() {
        failedAt.removeAll()
        version += 1
    }

    /// Stores from before editions were Briefs-only: unread passage editions are retired.
    func retirePassageEditions() {
        let passage = EditionKind.passage.rawValue, read = EditionState.read.rawValue, replaced = EditionState.replaced.rawValue
        let old = (try? context.fetch(FetchDescriptor<Edition>(predicate: #Predicate {
            $0.kindRaw == passage && $0.stateRaw != read && $0.stateRaw != replaced
        }))) ?? []
        guard !old.isEmpty else { return }
        for e in old { e.state = .replaced }
        library.save()
    }

    /// Signals that library content changed outside the scheduler (imports, samples).
    func touch() { version += 1 }

    // MARK: Refresh

    /// Call on launch, every half-minute, and whenever the schedule or library changes.
    func refresh(prefs: Preferences, now: Date = .now) {
        guard !prefs.isPaused(at: now) else { return }
        var changed = false
        for occurrence in SchedulePlanner.due(at: now, slots: prefs.slots) where edition(for: occurrence) == nil {
            if let created = prepare(occurrence, limit: prefs.editionLimit, now: now) {
                context.insert(created)
                changed = true
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

    private func prepare(_ occurrence: SlotOccurrence, limit: Int, now: Date) -> Edition? {
        let kind = briefKind(for: occurrence)
        if let brief = unreadBrief(of: kind) {
            return Edition(slotID: occurrence.slot.id, scheduledFor: occurrence.date, kind: .brief, brief: brief)
        }
        // With AI off there are no editions (SPEC › Scheduling); Today says so.
        if ai.isEnabled(.brief), failedAt[kind].map({ now.timeIntervalSince($0) > Self.retryAfter }) ?? true {
            generateBriefInBackground(kind, limit: limit) // The next refresh picks the new Brief up.
        }
        return nil
    }

    /// Unread editions from earlier slots become `replaced`.
    private func replaceOlder(than newest: Date) -> Bool {
        let all = (try? context.fetch(FetchDescriptor<Edition>())) ?? []
        let ids = Set(SchedulePlanner.toReplace(all.map { ($0.id, $0.scheduledFor, $0.state) }, newestReady: newest))
        for e in all where ids.contains(e.id) { e.state = .replaced }
        return !ids.isEmpty
    }

    // MARK: Reading

    func finish(brief: Brief, edition: Edition?) {
        brief.readAt = .now
        edition?.state = .read
        library.save()
        version += 1
    }

    // MARK: The Brief

    /// Gathers what the pipeline needs for `kind`, runs it off the main thread, and stores the Brief.
    func generateBriefInBackground(_ kind: BriefKind, limit: Int) {
        guard generating == nil, ai.isEnabled(.brief) else { return }
        let past = pastBriefs(of: kind)
        var request = BriefRequest(kind: kind, past: past.map(\.subject).filter { !$0.isEmpty } + past.map(\.title))
        let topic = kind == .topic ? Self.pickTopic(library.topics().filter { $0.isActive && $0.weight > 0.2 }) : nil
        let quote = kind == .quote ? library.quotes().first { $0.explainedAt == nil } : nil
        switch kind {
        case .topic:
            guard let topic else { return }
            request.topic = topic.label
            request.past = topic.pastAngles
            request.deeper = topic.deeperAngle
        case .quote:
            request.quote = quote?.text ?? ""
            request.author = quote?.author ?? ""
        case .news:
            request.feeds = library.feeds().map(\.url)
            request.seenLinks = Set(past.flatMap { $0.sources.map(\.url) })
            guard !request.feeds.isEmpty else { return }
        case .story:
            break
        }
        generating = kind
        let job = request
        let label = kind == .topic ? request.topic : kind.label
        Task {
            defer { generating = nil }
            guard let provider = await ai.availableProvider(for: .brief) else {
                failedAt[kind] = .now
                return
            }
            let draft: DraftBrief?
            do {
                draft = try await BriefPipeline.run(job, limit: limit, provider: provider)
            } catch {
                failedAt[kind] = .now // Offline or the provider failed: try again later.
                return
            }
            guard let draft else {
                // Nothing to ground it in. A reader's quote with no source is set aside so the next one gets a turn.
                if let quote {
                    quote.explainedAt = .now
                    quote.unsourced = true
                    library.save()
                } else {
                    failedAt[kind] = .now
                }
                version += 1
                return
            }
            topic?.pastAngles.append(draft.angle)
            topic?.deeperAngle = nil
            quote?.explainedAt = .now
            context.insert(Brief(kind: kind, topicLabel: label, title: draft.title, standfirst: draft.standfirst, body: draft.body,
                                 sources: draft.sources, subject: draft.subject))
            library.save()
            version += 1
        }
    }

    /// Recent Briefs of a kind, newest first, to avoid repeating angles, quotes or news items.
    private func pastBriefs(of kind: BriefKind) -> [Brief] {
        let raw = kind.rawValue
        var d = FetchDescriptor<Brief>(predicate: #Predicate { $0.kindRaw == raw }, sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
        d.fetchLimit = 60
        return (try? context.fetch(d)) ?? []
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
            content.body = "\(slot.content == .mix ? "The Brief" : slot.content.title), a few minutes long."
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
