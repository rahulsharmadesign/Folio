import AppKit
import Foundation
import Observation
import ServiceManagement
import SwiftData

/// What the reader is showing.
enum ReadingTarget {
    case passage(Part, Edition?)
    case brief(Brief, Edition?)
}

/// The edition just finished, for Edition complete (05).
struct FinishedEdition {
    var part: Part
    var edition: Edition?
    var slotName: String
}

/// App-wide state: navigation, preferences, and the services every screen uses.
@MainActor @Observable
final class AppState {
    /// For AppKit entry points (Open With, Dock drops) that can't reach the environment.
    nonisolated(unsafe) static weak var shared: AppState?

    var route: Route
    var reading: ReadingTarget?
    var finished: FinishedEdition?
    /// The reader's controls (04) are showing; the traffic lights follow them.
    var readerControlsVisible = false
    /// Updated every half-minute so time-based views (greeting, readiness) stay current.
    var now: Date = .now

    var prefs: Preferences {
        didSet {
            guard prefs != oldValue else { return }
            prefs.save()
            applyPreferences()
            if prefs.slots != oldValue.slots || prefs.quietArrival != oldValue.quietArrival {
                scheduler.scheduleNotifications(prefs: prefs)
            }
            if prefs.openAtLogin != oldValue.openAtLogin { applyLoginItem() }
            scheduler.refresh(prefs: prefs, now: now)
        }
    }

    /// `-FolioDesignFixtures YES` fills Today with the mockup's content for comparing against
    /// design/screens. Never on by default.
    let designFixtures: Bool
    private let isSnapshot: Bool

    let container: ModelContainer
    let theme: Theme
    let library: LibraryStore
    let ai: AIService
    let scheduler: EditionScheduler

    init(defaults: UserDefaults = .standard, inMemory: Bool = false) {
        designFixtures = defaults.bool(forKey: "FolioDesignFixtures")
        var loaded = Preferences.load(from: defaults)
        if designFixtures { loaded.onboarded = true }
        prefs = loaded

        let schema = Schema(FolioSchema.models)
        // DEBUG snapshots (tools/snap.sh) run against a fresh in-memory library with the samples.
        let snapshot = defaults.string(forKey: "FolioSnapshot") != nil
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemory || snapshot)
        isSnapshot = snapshot
        if let c = try? ModelContainer(for: schema, configurations: config) {
            container = c
        } else {
            // An unreadable store shouldn't stop the app; start clean in memory and say so in the log.
            container = try! ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true))
        }
        theme = Theme()
        library = LibraryStore(context: container.mainContext)
        ai = AIService()
        scheduler = EditionScheduler(library: library, ai: ai)

        let requested = defaults.string(forKey: "FolioRoute").flatMap(Route.init(rawValue:))
        route = requested ?? (loaded.onboarded ? .today : .onboarding)
        applyPreferences()
        Self.shared = self
    }

    // MARK: Lifecycle

    private var started = false

    func start() async {
        guard !started else { return }
        started = true
        await library.seedSamplesIfNeeded(limit: prefs.editionLimit, force: isSnapshot)
        scheduler.touch()
        if route == .reader, reading == nil, let part = library.currentWork?.nextPart {
            reading = .passage(part, nil) // -FolioRoute reader
        }
        scheduler.refresh(prefs: prefs, now: now)
        scheduler.scheduleNotifications(prefs: prefs)
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(30))
            now = .now
            scheduler.refresh(prefs: prefs, now: now)
        }
    }

    // MARK: Preferences → theme

    func applyPreferences() {
        theme.displayFamily = prefs.displayFamily
        theme.readingFamily = prefs.readingFamily
        theme.uiFamily = prefs.uiFamily
        theme.accent = Tokens.accents.first { $0.id == prefs.accentID } ?? Tokens.accentInk
        theme.reading = Tokens.themes.first { $0.id == prefs.themeID } ?? Tokens.paper
        theme.readingSize = CGFloat(prefs.textSize)
    }

    private func applyLoginItem() {
        do {
            if prefs.openAtLogin { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            // Unsigned development builds can't register; the toggle simply has no effect there.
        }
    }

    // MARK: Navigation

    func read(_ target: ReadingTarget) {
        reading = target
        route = target.isBrief ? .brief : .reader
    }

    /// Opens the next part of a serial right now (Library tile).
    func readNext(of work: Work) {
        guard let part = work.nextPart else { return }
        read(.passage(part, nil))
    }

    func finishPassage(_ part: Part, edition: Edition?) {
        scheduler.finish(part: part, edition: edition)
        let slotName = edition.flatMap { e in prefs.slots.first { $0.id == e.slotID }?.editionName } ?? SchedulePlanner.editionName(at: now)
        finished = FinishedEdition(part: part, edition: edition, slotName: slotName)
        route = .editionEnd
    }

    func importFiles(_ urls: [URL]) {
        Task {
            var last: Work?
            for url in urls {
                if let w = await library.importFile(at: url, limit: prefs.editionLimit) { last = w }
            }
            if last != nil {
                route = .library
                scheduler.refresh(prefs: prefs, now: now)
            }
        }
    }

    /// The sidebar's "Next edition" card.
    var nextEdition: NextEditionSummary? {
        if designFixtures { return DesignFixtures.nextEdition }
        _ = scheduler.version // re-read when the library changes
        guard let next = SchedulePlanner.next(after: now, slots: prefs.slots) else { return nil }
        return NextEditionSummary(when: SchedulePlanner.whenLabel(next.date, now: now), detail: detail(for: next.slot.content))
    }

    func detail(for content: SlotContent) -> String {
        let work = library.currentWork?.title
        let topic = library.topics().first { $0.isActive }?.label.lowercased()
        switch content {
        case .passage, .publication: return work.map { "Passage · \($0)" } ?? "Passage"
        case .brief:
            // One line in the sidebar card: long topics fall back to just "The Brief".
            return topic.flatMap { $0.count <= 16 ? "The Brief · \($0)" : nil } ?? "The Brief"
        case .passageAndBrief: return work.map { "\($0) + The Brief" } ?? "Passage + The Brief"
        }
    }
}

extension ReadingTarget {
    var isBrief: Bool {
        if case .brief = self { return true }
        return false
    }
}

extension SchedulePlanner {
    static func editionName(at date: Date, calendar: Calendar = .current) -> String {
        let h = calendar.component(.hour, from: date)
        return h < 12 ? "Morning edition" : h < 18 ? "Afternoon edition" : "Evening edition"
    }
}
