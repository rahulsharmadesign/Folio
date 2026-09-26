import SwiftData
import SwiftUI

/// Notebook & recall (08, Notebook.dc.html).
struct NotebookView: View {
    @Environment(AppState.self) private var app
    @Environment(Theme.self) private var theme
    @Environment(\.modelContext) private var context
    @Query(sort: \Highlight.createdAt, order: .reverse) private var highlights: [Highlight]
    @Query(sort: \Reflection.createdAt, order: .reverse) private var reflections: [Reflection]

    @State private var filter: Filter = .all
    @State private var question = ""
    @State private var answer = ""
    @State private var asking: Task<Void, Never>?

    enum Filter: String, CaseIterable, Hashable {
        case all, passages, briefs, reflections
        var title: String { rawValue.capitalized }
    }

    // Dot colours stated in Notebook.dc.html.
    private static let passageDot = RGBA(0x587AA8).color
    private static let reflectionDot = RGBA(0x7C8C62).color
    private static let briefDot = RGBA(0xC0985A).color

    private struct Entry: Identifiable {
        var id: String
        var text: String
        var italic: Bool
        var dot: Color
        var source: String
        var date: Date
        var note: String?
        var delete: () -> Void
    }

    private var entries: [Entry] {
        var list: [Entry] = []
        if filter != .reflections {
            for h in highlights where filter == .all || (filter == .passages) == (h.kind == .passage) {
                list.append(Entry(id: "h\(h.id)", text: h.text, italic: false, dot: h.kind == .passage ? Self.passageDot : Self.briefDot,
                                  source: h.kind == .brief ? "The Brief · \(h.sourceDetail)" : "\(h.sourceTitle) · \(h.sourceDetail)",
                                  date: h.createdAt, note: h.note, delete: { context.delete(h); try? context.save() }))
            }
        }
        if filter == .all || filter == .reflections {
            for r in reflections {
                guard let answer = r.answer, !answer.isEmpty else { continue }
                list.append(Entry(id: "r\(r.id)", text: answer, italic: true, dot: Self.reflectionDot,
                                  source: "Your reflection on \(r.sourceTitle)", date: r.createdAt, note: nil,
                                  delete: { context.delete(r); try? context.save() }))
            }
        }
        return list.sorted { $0.date > $1.date }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 48) {
            VStack(alignment: .leading, spacing: 26) {
                ScreenHeader(title: "Notebook", subtitle: "Your highlights, notes and reflections, in one quiet place.")
                SegmentedTabs(options: Filter.allCases, selection: $filter, height: 32, horizontalPadding: 14, fontSize: 13) { $0.title }
                ScrollView {
                    LazyVStack(spacing: 0) {
                        if entries.isEmpty {
                            Text(filter == .all
                                 ? "Nothing here yet. Select a phrase while reading, then choose Highlight or Save note."
                                 : "Nothing here yet.")
                                .uiText(14).foregroundStyle(theme.ink2)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, 20)
                        }
                        ForEach(entries) { entry in row(entry) }
                    }
                    .overlay(alignment: .top) { Rectangle().fill(theme.rule).frame(height: 1) }
                }
                .scrollIndicators(.never)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .leading, spacing: 20) {
                if let due = highlights.first(where: { $0.kept && Recall.isDue($0.nextReviewAt, now: app.now) }) {
                    resurfacing(due)
                }
                ask
            }
            .frame(width: 320)
            .padding(.top, 6)
        }
        .padding(.top, 64)
        .padding(.leading, 64)
        .padding(.trailing, 56)
        .padding(.bottom, 40)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func row(_ entry: Entry) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            CSSText(entry.text, style: TypeStyle(role: .reading, size: 18, lineHeight: 1.5, italic: entry.italic))
            if let note = entry.note {
                Text(note).uiText(13, lineHeight: 1.5).foregroundStyle(theme.ink2).fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 10) {
                Circle().fill(entry.dot).frame(width: 8, height: 8)
                Text(entry.source)
                Text("·").accessibilityHidden(true)
                Text(dateLabel(entry.date))
            }
            .uiText(13)
            .foregroundStyle(theme.ink2)
        }
        .padding(.vertical, 20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .bottom) { Rectangle().fill(theme.rule).frame(height: 1) }
        .contextMenu {
            Button("Copy") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(entry.text, forType: .string)
            }
            Button("Delete", role: .destructive, action: entry.delete)
        }
    }

    private func dateLabel(_ date: Date) -> String {
        Calendar.current.isDateInToday(date) ? "Today" : date.formatted(.dateTime.day().month(.abbreviated))
    }

    // MARK: Resurfacing today

    private func resurfacing(_ h: Highlight) -> some View {
        let shape = RoundedRectangle(cornerRadius: Tokens.Radius.card)
        return VStack(alignment: .leading, spacing: 14) {
            Kicker(text: "Resurfacing today", color: .inkOnWash)
            Text("“\(h.text)”")
                .readingText(20, italic: true, lineHeight: 1.45)
                .foregroundStyle(theme.ink)
                .fixedSize(horizontal: false, vertical: true)
            Text("\(h.sourceTitle) · \(h.sourceDetail) — highlighted \(Recall.ago(h.createdAt, now: app.now))")
                .uiText(13).foregroundStyle(theme.inkOnWash)
            let phrase = Recall.upcomingPhrase(afterStage: h.recallStage)
            if !phrase.isEmpty {
                Text(phrase).uiText(13, lineHeight: 1.5).foregroundStyle(theme.inkOnWash).fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 8) {
                Button("Keep") {
                    let next = Recall.keep(stage: h.recallStage, now: app.now)
                    h.recallStage = next.stage
                    h.nextReviewAt = next.next
                    try? context.save()
                }
                .buttonStyle(.primaryCompact)
                Button("Let it go") {
                    h.kept = false
                    h.nextReviewAt = nil
                    try? context.save()
                }
                .buttonStyle(LetGoStyle())
            }
            .padding(.top, 2)
        }
        .padding(.top, 24).padding(.horizontal, 22).padding(.bottom, 20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            theme.wash
                .overlay { WashStack(layers: [.right("wc-plum", -110, top: -90, 330, 235, opacity: 0.55)]) }
                .overlay { GrainLayer(opacity: 1) }
        }
        .clipShape(shape)
        .overlay(shape.strokeBorder(theme.rule, lineWidth: 1))
    }

    /// "Let it go" on the wash card: 1 px #CFC4AE border (Notebook.dc.html).
    private struct LetGoStyle: ButtonStyle {
        func makeBody(configuration: Configuration) -> some View {
            SecondaryButtonStyle(height: 40, horizontalPadding: 14, fontSize: 13, weight: 400).makeBody(configuration: configuration)
        }
    }

    // MARK: Ask your notebook

    private var ask: some View {
        let shape = RoundedRectangle(cornerRadius: Tokens.Radius.card)
        return VStack(alignment: .leading, spacing: 12) {
            Kicker(text: "Ask your notebook")
            TextField("", text: $question, prompt: Text("What keeps coming up?").foregroundStyle(theme.ink3))
                .textFieldStyle(.plain)
                .uiText(14)
                .foregroundStyle(theme.ink)
                .padding(.horizontal, 12)
                .frame(height: 42)
                .background(theme.background, in: RoundedRectangle(cornerRadius: Tokens.Radius.control))
                .overlay(RoundedRectangle(cornerRadius: Tokens.Radius.control).strokeBorder(theme.controlSoft, lineWidth: 1))
                .onSubmit { run(question) }
                .accessibilityLabel("Ask your notebook")
            VStack(alignment: .leading, spacing: 6) {
                suggestion("What connects my highlights this month?")
                suggestion("Turn this week into a one-page digest")
            }
            if !answer.isEmpty {
                Text(answer).uiText(14, lineHeight: 1.5).foregroundStyle(theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
        }
        .padding(.vertical, 20)
        .padding(.horizontal, 22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.surface, in: shape)
        .overlay(shape.strokeBorder(theme.rule, lineWidth: 1))
    }

    private func suggestion(_ text: String) -> some View {
        Button {
            question = text
            run(text)
        } label: {
            Text(text).uiText(13).foregroundStyle(theme.ink)
                .padding(.horizontal, 10)
                .frame(maxWidth: .infinity, minHeight: 36, alignment: .leading)
                .background(theme.wash, in: RoundedRectangle(cornerRadius: 8))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func run(_ q: String) {
        let q = q.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return }
        asking?.cancel()
        answer = "…"
        let notes = highlights.prefix(60).map { h in "“\(h.text)” — \(h.sourceTitle), \(h.sourceDetail)\(h.note.map { ". Note: \($0)" } ?? "")" }
            + reflections.prefix(30).compactMap { r in r.answer.map { "Reflection on \(r.sourceTitle): \($0)" } }
        guard !notes.isEmpty else {
            answer = "Your notebook is empty so far. Highlights and reflections you save will show up here."
            return
        }
        asking = Task {
            guard let provider = await app.ai.availableProvider(for: .notebook) else {
                answer = "Asking your notebook needs an AI provider. Choose one in Folio › Settings › AI."
                return
            }
            answer = ""
            do {
                for try await chunk in provider.stream(Prompts.notebook(question: q, notes: Array(notes))) {
                    if Task.isCancelled { return }
                    answer += chunk
                }
            } catch {
                answer = (error as? LocalizedError)?.errorDescription ?? "Something went wrong."
            }
        }
    }
}
