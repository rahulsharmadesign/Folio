import SwiftData
import SwiftUI

/// Today (02, Main.dc.html): greeting, today's Brief cards, "Continue reading", a resurfaced highlight, and the closing line.
struct TodayView: View {
    @Environment(Theme.self) private var theme
    @Environment(AppState.self) private var app
    @Environment(\.modelContext) private var context
    @Query(sort: \Highlight.createdAt) private var highlights: [Highlight]
    @Query(sort: \Brief.createdAt) private var briefs: [Brief]
    @Query private var works: [Work]

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            header

            if app.designFixtures {
                DesignFixtures.TodayEditions()
                DesignFixtures.TodayResurfaced()
            } else {
                let book = cards.count < 3 ? app.library.currentWork : nil
                if !cards.isEmpty || book != nil {
                    HStack(alignment: .top, spacing: 24) {
                        ForEach(cards) { card in
                            editionCard(card).frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                        if let book {
                            bookCard(book).frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                    }
                    .fixedSize(horizontal: false, vertical: true)
                }
                if let due = dueHighlight { resurfaced(due) }
            }

            // `margin-top: auto`: pinned to the bottom, or straight after the content when it overflows.
            Text("Nothing else today. That’s the point.")
                .displayText(16, italic: true)
                .foregroundStyle(theme.ink2)
                .frame(maxHeight: .infinity, alignment: .bottomLeading)
        }
        .padding(.top, 56)
        .padding(.horizontal, 72)
        .padding(.bottom, 40)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .id(app.scheduler.version)
    }

    private var now: Date { app.designFixtures ? DesignFixtures.now : app.now }
    private var name: String? { app.designFixtures ? "Rahul" : Greeting.firstName }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(Greeting.dateLine(for: now))
                .uiText(13, tracking: 0.01)
                .foregroundStyle(theme.ink2)
            Text(Greeting.greeting(for: now, name: name))
                .textStyle(Tokens.greeting)
                .foregroundStyle(theme.ink)
                .accessibilityAddTraits(.isHeader)
            Text(status)
                .uiText(16)
                .foregroundStyle(theme.ink2)
        }
    }

    // MARK: Cards

    private struct Card: Identifiable {
        enum State { case ready, upcoming, read, missed }
        var id: String
        var occurrence: SlotOccurrence
        var state: State
        var edition: Edition?
        var brief: Brief?
    }

    /// One card per delivery today that has its Brief (an upcoming one shows the Brief waiting for it).
    private var cards: [Card] {
        guard app.scheduler.version >= 0 else { return [] }
        return SchedulePlanner.occurrences(of: app.prefs.slots, on: now).prefix(3).compactMap { occurrence in
            let edition = app.scheduler.edition(for: occurrence)
            let state: Card.State = switch edition?.state {
            case .read: .read
            case .replaced: .missed
            case .ready: .ready
            default: occurrence.date <= now ? .ready : .upcoming
            }
            guard let brief = edition?.brief ?? app.scheduler.unreadBrief(of: app.scheduler.briefKind(for: occurrence)) else { return nil }
            return Card(id: occurrence.slot.id, occurrence: occurrence, state: state, edition: edition, brief: brief)
        }
    }

    private var status: String {
        if app.designFixtures { return "Your morning edition is ready. About four minutes." }
        if !app.ai.isEnabled(.brief), cards.isEmpty {
            // Not in the designs: editions are Briefs, so they need an AI provider.
            return "Editions are written by AI. Choose a provider in Settings › AI and they’ll arrive here."
        }
        if app.prefs.isPaused(at: now) { return "Editions are paused for today." }
        if let ready = cards.first(where: { $0.state == .ready }) {
            let chars = ready.brief?.charCount ?? Chunker.defaultLimit
            return "Your \(ready.occurrence.slot.editionName.lowercased()) is ready. \(ReadingTime.aboutWords(chars))"
        }
        if let next = cards.first(where: { $0.state == .upcoming }) {
            return "Your \(next.occurrence.slot.editionName.lowercased()) arrives at \(next.occurrence.slot.time)."
        }
        if let latest = SchedulePlanner.latestToday(before: now, slots: app.prefs.slots), app.scheduler.edition(for: latest) == nil {
            // Not in the designs: the slot has arrived but its Brief is still being written (or couldn't be).
            return "Your \(latest.slot.editionName.lowercased()) is being written. It’ll be here shortly."
        }
        if !cards.isEmpty { return "You’ve read today’s editions." }
        if let next = SchedulePlanner.next(after: now, slots: app.prefs.slots) {
            return "Your next edition arrives \(SchedulePlanner.whenLabel(next.date, now: now).lowercased())."
        }
        return "Set a time in Schedule and your editions will arrive then."
    }

    @ViewBuilder
    private func editionCard(_ card: Card) -> some View {
        let slotLabel = "\(card.occurrence.slot.editionName) · \(card.occurrence.slot.time)"
        let badge: EditionBadge = switch card.state {
        case .ready: EditionBadge(text: slotLabel, kind: .ready)
        case .upcoming: EditionBadge(text: slotLabel, kind: .upcoming)
        case .read: EditionBadge(text: "\(card.occurrence.slot.editionName) · read", kind: .upcoming)
        case .missed: EditionBadge(text: "\(card.occurrence.slot.editionName) · missed", kind: .upcoming)
        }
        if let brief = card.brief {
            EditionCard(
                washes: washes(for: brief.kind),
                badge: badge,
                kicker: brief.kind == .topic ? "The Brief · written for you" : "The Brief · \(brief.kind.label.lowercased())",
                title: brief.title,
                meta: "\(origin(brief)) · \(ReadingTime.minutes(brief.charCount)) min"
            ) {
                actions(card, target: .brief(brief, card.edition))
            }
        }
    }

    private func origin(_ brief: Brief) -> String {
        switch brief.kind {
        case .topic: "From your topic: \(brief.topicLabel.lowercased())"
        case .story: "A true story, with sources"
        case .quote: "\(brief.sources.count) source\(brief.sources.count == 1 ? "" : "s")"
        case .news: "From your news feeds"
        }
    }

    private func washes(for kind: BriefKind) -> [WashLayer] {
        switch kind {
        case .topic: [.left("wc-ochre", 30, top: -50, 400, 285, opacity: 0.8), .right("wc-rose", -90, top: 40, 340, 242, opacity: 0.6)]
        case .story: [.left("wc-rose", 30, top: -50, 400, 285, opacity: 0.8), .right("wc-ochre", -90, top: 40, 340, 242, opacity: 0.6)]
        case .quote: [.left("wc-plum", 30, top: -50, 400, 285, opacity: 0.75), .right("wc-lapis", -90, top: 40, 340, 242, opacity: 0.55)]
        case .news: [.left("wc-sage", 30, top: -50, 400, 285, opacity: 0.8), .right("wc-lapis", -90, top: 40, 340, 242, opacity: 0.6)]
        }
    }

    /// Not in the designs: the book in progress, in the edition card's form.
    private func bookCard(_ work: Work) -> some View {
        let part = work.nextPart
        let chapter = part?.chapterTitle ?? ""
        return EditionCard(
            washes: [.left(work.coverWash, -40, top: -70, 420, 300, opacity: 0.9), .right("wc-sage", -60, top: 10, 360, 256, opacity: 0.75)],
            badge: EditionBadge(text: "Your book · \(work.progressLabel)", kind: .upcoming),
            kicker: [work.title, work.author].filter { !$0.isEmpty }.joined(separator: " · "),
            title: chapter.isEmpty ? work.title : chapter,
            meta: work.nextPartIndex == 0 ? "From the beginning" : "Picks up where you stopped"
        ) {
            Button { app.readBook(work) } label: {
                ButtonLabel(title: work.nextPartIndex == 0 ? "Start reading" : "Continue reading", trailingIcon: .arrowRight)
            }
            .buttonStyle(.secondary)
        }
    }

    @ViewBuilder
    private func actions(_ card: Card, target: ReadingTarget) -> some View {
        switch card.state {
        case .ready:
            Button { app.read(target) } label: { ButtonLabel(title: "Begin reading", trailingIcon: .arrowRight) }
                .buttonStyle(.primary)
        case .upcoming:
            let when = card.occurrence.date.timeIntervalSince(now) < 12 * 3600 && Calendar.current.component(.hour, from: card.occurrence.date) >= 18
                ? "Arrives tonight" : "Arrives at \(card.occurrence.slot.time)"
            Button("\(when) · peek") { app.read(target) }.buttonStyle(.secondary)
        case .read:
            Button("Read again") { app.read(target) }.buttonStyle(.secondary)
        case .missed:
            Button("Read anyway") { app.read(target) }.buttonStyle(.secondary)
            Text("The next edition took its place").uiText(13).foregroundStyle(theme.ink2)
        }
    }

    // MARK: Resurfaced

    private var dueHighlight: Highlight? {
        highlights.first { $0.kept && Recall.isDue($0.nextReviewAt, now: now) }
    }

    private func resurfaced(_ h: Highlight) -> some View {
        QuoteCard(
            kicker: "Back from \(Recall.ago(h.createdAt, now: now))",
            quote: "“\(h.text)”",
            source: "\(h.sourceTitle) · \(h.sourceDetail)"
        ) {
            Button("Keep") { keep(h) }.buttonStyle(.secondaryCompact)
            Button("Let it go") { letGo(h) }.buttonStyle(.quiet)
        }
    }

    private func keep(_ h: Highlight) {
        let next = Recall.keep(stage: h.recallStage, now: now)
        h.recallStage = next.stage
        h.nextReviewAt = next.next
        try? context.save()
    }

    private func letGo(_ h: Highlight) {
        h.kept = false
        h.nextReviewAt = nil
        try? context.save()
    }
}

enum Greeting {
    static func greeting(for date: Date, name: String?, calendar: Calendar = .current) -> String {
        let hour = calendar.component(.hour, from: date)
        let part = hour < 12 ? "morning" : hour < 18 ? "afternoon" : "evening"
        if let name, !name.isEmpty { return "Good \(part), \(name)." }
        return "Good \(part)."
    }

    /// "Saturday, 26 September"
    static func dateLine(for date: Date, locale: Locale = .current) -> String {
        date.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(locale))
    }

    static var firstName: String? {
        NSFullUserName().split(separator: " ").first.map(String.init)
    }
}
