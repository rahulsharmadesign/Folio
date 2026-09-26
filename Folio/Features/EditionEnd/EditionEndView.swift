import SwiftData
import SwiftUI

/// Edition complete (05, End.dc.html): a question to carry, a rating, what's next, and "Close for now".
struct EditionEndView: View {
    @Environment(AppState.self) private var app
    @Environment(Theme.self) private var theme
    @Environment(\.modelContext) private var context

    @State private var question: String?
    @State private var reflection = ""
    @State private var rating: String?
    @FocusState private var editorFocused: Bool

    private static let ratings = ["too easy", "just right", "a stretch"]
    /// Shown when the reflection question can't be written by AI. Not in the designs; flagged for review.
    private static let fallbackQuestion = "What’s one line from this passage you’d like to remember?"

    var body: some View {
        GeometryReader { geo in
            let palette = theme.reading
            let dx = (geo.size.width - 1280) / 2
            ZStack(alignment: .topLeading) {
                palette.background.color
                WashStack(layers: [
                    .left("wc-lapis", 470 + dx, top: 36, 340, 242, opacity: 0.55),
                    .left("wc-sage", 560 + dx, top: 70, 260, 185, opacity: 0.45),
                ])
                GrainLayer(opacity: palette.grainOpacity)

                VStack(spacing: 28) {
                    VStack(spacing: 12) {
                        Kicker(text: "\(slotName) · complete", tracking: 0.08)
                        Text("That’s all for \(partOfDay).")
                            .textStyle(Tokens.editionEnd)
                            .foregroundStyle(palette.ink.color)
                            .multilineTextAlignment(.center)
                            .accessibilityAddTraits(.isHeader)
                    }
                    questionCard
                    whatsNext
                    Button { app.route = .today } label: {
                        Text("Close for now").uiText(14, weight: 500).foregroundStyle(theme.accentColor)
                            .padding(.horizontal, 12).frame(height: 44).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut(.escape, modifiers: [])
                }
                .frame(width: 600)
                .offset(x: (geo.size.width - 600) / 2, y: 150)
            }
            .environment(readingTheme(palette))
        }
        .ignoresSafeArea()
        .task { await loadQuestion() }
    }

    private func readingTheme(_ palette: Palette) -> Theme {
        let t = Theme()
        t.palette = palette
        t.accent = theme.accent
        t.displayFamily = theme.displayFamily
        t.readingFamily = theme.readingFamily
        t.uiFamily = theme.uiFamily
        return t
    }

    private var slotName: String { app.finished?.slotName ?? SchedulePlanner.editionName(at: app.now) }

    private var partOfDay: String {
        switch slotName {
        case "Morning edition": "this morning"
        case "Afternoon edition": "this afternoon"
        default: "this evening"
        }
    }

    // MARK: A question to carry

    private var questionCard: some View {
        let palette = theme.reading
        let shape = RoundedRectangle(cornerRadius: Tokens.Radius.card)
        return VStack(alignment: .leading, spacing: 14) {
            Kicker(text: "A question to carry")
            CSSText(question ?? " ", style: TypeStyle(role: .reading, size: 19, lineHeight: 1.5), color: palette.ink.color)
                .opacity(question == nil ? 0 : 1)
            ZStack(alignment: .topLeading) {
                if reflection.isEmpty {
                    Text("Write a line — or just think about it.")
                        .uiText(15, lineHeight: 1.5)
                        .foregroundStyle(palette.ink3.color)
                        .padding(.horizontal, 14).padding(.vertical, 12)
                        .allowsHitTesting(false)
                }
                TextEditor(text: $reflection)
                    .font(Fonts.font(family: theme.uiFamily, size: 15))
                    .foregroundStyle(palette.ink.color)
                    .scrollContentBackground(.hidden)
                    .padding(.horizontal, 9).padding(.vertical, 12)
                    .focused($editorFocused)
                    .accessibilityLabel("Your reflection")
            }
            .frame(height: 70)
            .background(palette.background.color, in: RoundedRectangle(cornerRadius: Tokens.Radius.control))
            .overlay(RoundedRectangle(cornerRadius: Tokens.Radius.control).strokeBorder(palette.controlSoft.color, lineWidth: 1))

            HStack {
                HStack(spacing: 6) {
                    Text("This passage was").uiText(13).foregroundStyle(palette.ink2.color).padding(.trailing, 4)
                    ForEach(Self.ratings, id: \.self) { r in
                        let on = rating == r
                        Button { rating = on ? nil : r } label: {
                            Text(r).uiText(13)
                                .foregroundStyle(on ? theme.primaryForeground : palette.ink.color)
                                .padding(.horizontal, 12).frame(height: 34)
                                .background(on ? theme.primaryBackground : .clear, in: Capsule(style: .circular))
                                .overlay(Capsule(style: .circular).strokeBorder(on ? theme.primaryBackground : palette.control.color, lineWidth: 1))
                                .contentShape(Capsule(style: .circular))
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(on ? .isSelected : [])
                    }
                }
                .accessibilityElement(children: .contain)
                .accessibilityLabel("How was this passage?")
                Spacer()
                Button("Save to notebook", action: save)
                    .buttonStyle(PrimaryButtonStyle(height: 40, horizontalPadding: 16, fontSize: 13))
            }
        }
        .padding(.top, 24).padding(.horizontal, 24).padding(.bottom, 20)
        .background(palette.surface.color, in: shape)
        .overlay(shape.strokeBorder(palette.rule.color, lineWidth: 1))
    }

    private func save() {
        guard let finished = app.finished else { app.route = .notebook; return }
        finished.edition?.rating = rating
        let text = reflection.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty {
            context.insert(Reflection(prompt: question ?? Self.fallbackQuestion, answer: text, sourceTitle: finished.part.work?.title ?? ""))
        }
        try? context.save()
        app.route = .notebook
    }

    private func loadQuestion() async {
        guard question == nil, let finished = app.finished else {
            if question == nil { question = Self.fallbackQuestion }
            return
        }
        rating = finished.edition?.rating ?? "just right"
        let work = finished.part.work
        if let provider = await app.ai.availableProvider(for: .reflection),
           let q = try? await provider.complete(Prompts.reflection(part: finished.part.text,
                                                                    work: .init(title: work?.title ?? "", author: work?.author ?? "", chapter: finished.part.chapterTitle))) {
            question = q.trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            question = Self.fallbackQuestion
        }
    }

    // MARK: What's next

    private struct NextItem: Identifiable {
        var id: String
        var when: String
        var title: String
        var brief: Brief?
    }

    private var nextItems: [NextItem] {
        var items: [NextItem] = []
        var cursor = app.now
        var seen = 0
        while items.count < 2, seen < 6, let next = SchedulePlanner.next(after: cursor, slots: app.prefs.slots) {
            seen += 1
            cursor = next.date
            let when = SchedulePlanner.whenLabel(next.date, now: app.now).replacingOccurrences(of: ", ", with: " · ")
            switch next.slot.content {
            case .brief:
                let brief = unreadBrief
                items.append(NextItem(id: "\(next.date)", when: when, title: "The Brief — " + (brief?.title ?? "a topic from your list"), brief: brief))
            default:
                items.append(NextItem(id: "\(next.date)", when: when, title: nextPassageTitle))
            }
        }
        return items
    }

    private var unreadBrief: Brief? {
        let d = FetchDescriptor<Brief>(predicate: #Predicate { $0.readAt == nil }, sortBy: [SortDescriptor(\.createdAt)])
        return try? context.fetch(d).first
    }

    private var nextPassageTitle: String {
        guard let work = app.library.currentWork, let part = work.nextPart else { return "Your next serial" }
        let continues = app.finished?.part.chapterTitle == part.chapterTitle && app.finished?.part.work?.id == work.id
        return "\(work.title), part \(part.index + 1) — " + (continues ? "the chapter continues" : (part.chapterTitle.isEmpty ? "the next part" : part.chapterTitle))
    }

    private var whatsNext: some View {
        let palette = theme.reading
        return VStack(spacing: 0) {
            ForEach(nextItems) { item in
                Button {
                    if let brief = item.brief { app.read(.brief(brief, nil)) }
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.when).uiText(12).foregroundStyle(palette.ink2.color)
                            Text(item.title).displayText(18).foregroundStyle(palette.ink.color).lineLimit(1)
                        }
                        Spacer()
                        if item.brief != nil {
                            IconView(icon: .chevronRight, size: 18, strokeWidth: 1.5).foregroundStyle(palette.ink2.color)
                        }
                    }
                    .frame(minHeight: 56)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .allowsHitTesting(item.brief != nil)
                .overlay(alignment: .bottom) { Rectangle().fill(palette.rule.color).frame(height: 1) }
            }
        }
        .overlay(alignment: .top) { Rectangle().fill(palette.rule.color).frame(height: 1) }
    }
}
