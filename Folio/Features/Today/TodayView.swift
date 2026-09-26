import SwiftData
import SwiftUI

/// Today (02, Main.dc.html): greeting, today's edition cards, a resurfaced highlight, and the closing line.
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
                if !cards.isEmpty {
                    HStack(alignment: .top, spacing: 24) {
                        ForEach(cards) { card in
                            editionCard(card).frame(maxWidth: .infinity, maxHeight: .infinity)
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
        var part: Part?
        var brief: Brief?
    }

    private var cards: [Card] {
        guard app.scheduler.version >= 0 else { return [] }
        var result: [Card] = []
        for occurrence in SchedulePlanner.occurrences(of: app.prefs.slots, on: now).prefix(3) {
            let kinds: [EditionKind] = occurrence.slot.content == .passageAndBrief ? [.passage, .brief]
                : occurrence.slot.content == .brief ? [.brief] : [.passage]
            for kind in kinds {
                let edition = app.scheduler.edition(for: occurrence, kind: kind)
                    ?? (kind == .brief ? app.scheduler.edition(for: occurrence, kind: .passage) : nil)
                let arrived = occurrence.date <= now
                let state: Card.State = switch edition?.state {
                case .read: .read
                case .replaced: .missed
                case .ready: .ready
                default: arrived ? .ready : .upcoming
                }
                var card = Card(id: "\(occurrence.slot.id)-\(kind.rawValue)", occurrence: occurrence, state: state, edition: edition)
                if let edition {
                    card.part = edition.part
                    card.brief = edition.brief
                } else if kind == .brief, let brief = briefs.first(where: { $0.readAt == nil }) {
                    card.brief = brief
                } else {
                    card.part = app.library.currentWork?.nextPart
                }
                if card.part != nil || card.brief != nil { result.append(card) }
            }
        }
        return result
    }

    private var status: String {
        if app.designFixtures { return "Your morning edition is ready. About four minutes." }
        if works.isEmpty && briefs.isEmpty {
            return "No editions yet. Add a book in Library and your first one will be here."
        }
        if app.prefs.isPaused(at: now) { return "Editions are paused for today." }
        if let ready = cards.first(where: { $0.state == .ready }) {
            let chars = ready.part?.charCount ?? ready.brief?.charCount ?? Chunker.defaultLimit
            return "Your \(ready.occurrence.slot.editionName.lowercased()) is ready. \(ReadingTime.aboutWords(chars))"
        }
        if let next = cards.first(where: { $0.state == .upcoming }) {
            return "Your \(next.occurrence.slot.editionName.lowercased()) arrives at \(next.occurrence.slot.time)."
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
                washes: [.left("wc-ochre", 30, top: -50, 400, 285, opacity: 0.8), .right("wc-rose", -90, top: 40, 340, 242, opacity: 0.6)],
                badge: badge,
                kicker: "The Brief · written for you",
                title: brief.title,
                meta: "From your topic: \(brief.topicLabel.lowercased()) · \(ReadingTime.minutes(brief.charCount)) min"
            ) {
                actions(card, target: .brief(brief, card.edition))
            }
        } else if let part = card.part, let work = part.work {
            EditionCard(
                washes: [.left(work.coverWash, -40, top: -70, 420, 300, opacity: 0.9), .right("wc-sage", -60, top: 10, 360, 256, opacity: 0.75)],
                badge: badge,
                kicker: "Passage · \(work.title), part \(part.index + 1) of \(work.partCount)",
                title: part.chapterTitle.isEmpty ? work.title : part.chapterTitle,
                meta: [work.author, "\(ReadingTime.minutes(part.charCount)) min"].filter { !$0.isEmpty }.joined(separator: " · ")
            ) {
                actions(card, target: .passage(part, card.edition), continues: part.index > 0)
            }
        }
    }

    @ViewBuilder
    private func actions(_ card: Card, target: ReadingTarget, continues: Bool = false) -> some View {
        switch card.state {
        case .ready:
            Button { app.read(target) } label: { ButtonLabel(title: "Begin reading", trailingIcon: .arrowRight) }
                .buttonStyle(.primary)
            if !target.isBrief {
                Text(continues ? "Continues from yesterday" : "The first part").uiText(13).foregroundStyle(theme.ink2)
            }
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
