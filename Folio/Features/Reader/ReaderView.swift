import SwiftData
import SwiftUI

/// The paged reader for passages (03, 03b, 04) and Briefs (06, 06b).
struct ReaderView: View {
    @Environment(AppState.self) private var app
    @Environment(Theme.self) private var theme
    @Environment(\.modelContext) private var context
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Query private var highlights: [Highlight]

    @State private var page = 0
    @State private var layout = PageLayout(ranges: [], lastPageUsedHeight: 0)
    @State private var hideTask: Task<Void, Never>?
    @State private var selection: Selection?
    @State private var explainMode: ExplainMode = .explain
    @State private var answer = ""
    @State private var footnote: String?
    @State private var question = ""
    @State private var aiTask: Task<Void, Never>?
    @State private var monitor: Any?
    @State private var swipeX: CGFloat = 0
    @State private var briefFeedback: BriefFeedback?

    private struct Selection: Equatable {
        var range: NSRange
        var rect: CGRect
    }

    private enum BriefFeedback { case deeper, more, less }

    var body: some View {
        GeometryReader { geo in
            if let content = content(size: geo.size) {
                reader(content, size: geo.size)
            } else {
                EmptyFullScreen(title: "Nothing to read yet")
            }
        }
        .ignoresSafeArea()
        .onAppear(perform: installMonitor)
        .onDisappear {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
            aiTask?.cancel()
            app.readerControlsVisible = false
        }
    }

    // MARK: Content

    private struct Content {
        var text: NSAttributedString
        /// Characters before the body (recap, Brief heading), to map highlight ranges.
        var bodyOffset: Int
        var top: CGFloat
        var footerHeight: CGFloat
        var runningHead: String
        var footerLeft: String
        var controlsTitle: String
        var controlsSubtitle: String
        var trailerReserve: CGFloat
        var cssShift: CGFloat
        var totalCharacters: Int
        var sourceID: UUID?
        var partIndex: Int?
        var kind: HighlightKind
        var sourceTitle: String
        var sourceDetail: String
        var workContext: Prompts.WorkContext
        var plainText: String
    }

    private var style: ReaderText.Style {
        ReaderText.Style(readingFamily: theme.readingFamily, displayFamily: theme.displayFamily, uiFamily: theme.uiFamily,
                         size: theme.readingSize, ink: theme.reading.ink.nsColor, ink2: theme.reading.ink2.nsColor)
    }

    private func content(size: CGSize) -> Content? {
        switch app.reading {
        case .passage(let part, _):
            guard let work = part.work else { return nil }
            let recap = part.index > 0 ? part.recap : nil
            let text = ReaderText.passage(part.text, recap: recap, style: style)
            let bodyOffset = text.length - (part.text as NSString).length
            let chapter = part.chapterTitle.isEmpty ? work.title : part.chapterTitle
            return Content(
                text: text, bodyOffset: bodyOffset, top: 124, footerHeight: 72,
                runningHead: chapter,
                footerLeft: "\(work.title) · part \(part.index + 1) of \(work.partCount)",
                controlsTitle: work.title,
                controlsSubtitle: "\(chapter) · part \(part.index + 1) of \(work.partCount)",
                trailerReserve: 118,
                cssShift: ReaderText.cssShift(style: style, lineHeight: 1.66),
                totalCharacters: part.charCount,
                sourceID: work.id, partIndex: part.index, kind: .passage, sourceTitle: work.title, sourceDetail: chapter,
                workContext: .init(title: work.title, author: work.author, chapter: part.chapterTitle),
                plainText: part.text)
        case .brief(let brief, let edition):
            let text = ReaderText.brief(kicker: brief.topicLabel, title: brief.title, standfirst: brief.standfirst, body: brief.body, style: style)
            let bodyLength = ReaderText.body(brief.body, style: style, lineHeight: 1.6, gapEm: 1, smallCapsOpening: false, italicMarkup: true).length
            let slot = edition.flatMap { e in app.prefs.slots.first { $0.id == e.slotID } }
            let n = CGFloat(brief.sources.count)
            return Content(
                text: text, bodyOffset: text.length - bodyLength, top: 108, footerHeight: 64,
                runningHead: "The Brief · \(slot?.editionName ?? SchedulePlanner.editionName(at: brief.createdAt))",
                footerLeft: "The Brief · topic: \(brief.topicLabel.lowercased())",
                controlsTitle: "The Brief",
                controlsSubtitle: brief.title,
                trailerReserve: 26 + 1 + 16 + 16 + 12 + n * 21 + max(0, n - 1) * 4 + 18 + 40 + 8,
                cssShift: ReaderText.cssShift(style: style, lineHeight: 1.6),
                totalCharacters: brief.charCount,
                sourceID: brief.id, partIndex: nil, kind: .brief, sourceTitle: "The Brief", sourceDetail: brief.topicLabel,
                workContext: .init(title: brief.title, author: "", chapter: ""),
                plainText: brief.body)
        case nil:
            return nil
        }
    }

    private var pageCount: Int { max(1, layout.ranges.count) }
    private var isLastPage: Bool { page >= pageCount - 1 }
    private var palette: Palette { theme.reading }

    // MARK: Layout

    private func reader(_ c: Content, size: CGSize) -> some View {
        let columnX = max(24, (size.width - Tokens.Reader.measure) / 2)
        let pageHeight = size.height - c.top - 68
        let zone = min(Tokens.Reader.pageTurnZoneWidth, columnX - 8)
        let markers = highlightRanges(c)

        return ZStack(alignment: .topLeading) {
            palette.background.color
            if c.kind == .brief, page == 0 {
                WashStack(layers: [.right("wc-ochre", -120, top: -130, 560, 400, opacity: 0.5)])
            }
            GrainLayer(opacity: palette.grainOpacity)

            PagedReader(
                text: c.text, pageSize: CGSize(width: Tokens.Reader.measure, height: pageHeight), page: page,
                lastPageReserve: c.trailerReserve, cssShift: c.cssShift, markers: markers,
                markerColor: Tokens.highlightFill.nsColor, reduceMotion: reduceMotion,
                onLayout: { new in
                    layout = new
                    page = min(page, max(0, new.ranges.count - 1))
                },
                onSelect: { range, rect in select(range, rect: rect, content: c) },
                onDeselect: { if selection != nil, question.isEmpty { closeExplain() } }
            )
            .frame(width: Tokens.Reader.measure, height: pageHeight)
            .offset(x: columnX, y: c.top)

            if isLastPage, !layout.ranges.isEmpty {
                trailer(c)
                    .frame(width: Tokens.Reader.measure)
                    .offset(x: columnX, y: c.top + layout.lastPageUsedHeight - c.cssShift)
            }

            // Edge zones: a click in the outer 260 pt turns the page.
            turnZone(width: zone, label: "Previous page") { turn(-1) }
                .offset(y: 90).frame(height: max(0, size.height - 180))
            turnZone(width: zone, label: "Next page") { turn(1) }
                .offset(x: size.width - zone, y: 90).frame(height: max(0, size.height - 180))

            if app.readerControlsVisible {
                controlsHeader(c, width: size.width)
                controlsFooter(c, width: size.width).offset(y: size.height - 72)
            } else {
                focusHeader(c, width: size.width)
                focusFooter(c, width: size.width).offset(y: size.height - c.footerHeight)
            }

            if let selection {
                explainPopover(c, selection: selection, columnX: columnX, size: size)
            }
        }
        .frame(width: size.width, height: size.height)
        .onContinuousHover { phase in
            if case .active = phase { showControls() }
        }
        .onChange(of: page) { _, new in
            closeExplain()
            if new >= pageCount - 1, case .brief(let brief, let edition) = app.reading, brief.readAt == nil {
                app.scheduler.finish(brief: brief, edition: edition)
            }
        }
        .task(id: recapKey) { await loadRecap() }
    }

    private func turnZone(width: CGFloat, label: String, action: @escaping () -> Void) -> some View {
        Color.clear
            .frame(width: max(0, width))
            .contentShape(Rectangle())
            .onTapGesture(perform: action)
            .accessibilityElement()
            .accessibilityLabel(label)
            .accessibilityAddTraits(.isButton)
            .accessibilityAction(.default, action)
    }

    // MARK: Focus chrome (03)

    private func focusHeader(_ c: Content, width: CGFloat) -> some View {
        HStack {
            backButton(color: theme.readingInk3, size: 13)
            Spacer()
            Text(c.runningHead).displayText(15, italic: true).foregroundStyle(theme.readingInk3).lineLimit(1)
            Spacer()
            if c.kind == .passage {
                Button(action: showControlsPinned) {
                    IconView(icon: .menu, size: 20, strokeWidth: 1.5)
                        .foregroundStyle(theme.readingInk3)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Show controls")
            } else {
                Color.clear.frame(width: 60, height: 44)
            }
        }
        .padding(.horizontal, 28)
        .frame(width: width, height: 72)
    }

    private func focusFooter(_ c: Content, width: CGFloat) -> some View {
        HStack(spacing: 0) {
            Text(c.footerLeft).frame(maxWidth: .infinity, alignment: .leading)
            ProgressHairline(progress: Double(page + 1) / Double(pageCount), width: 140, fill: palette.ink2.color)
                .environment(readingTheme)
                .frame(maxWidth: .infinity)
            Text(pageLabel(c, long: false)).frame(maxWidth: .infinity, alignment: .trailing)
        }
        .uiText(12)
        .foregroundStyle(theme.readingInk3)
        .lineLimit(1)
        .padding(.horizontal, 36)
        .frame(width: width, height: c.footerHeight)
    }

    /// A Theme whose chrome palette is the reading palette (for shared components in the reader).
    private var readingTheme: Theme {
        let t = Theme()
        t.palette = palette
        t.accent = theme.accent
        t.displayFamily = theme.displayFamily
        t.readingFamily = theme.readingFamily
        t.uiFamily = theme.uiFamily
        return t
    }

    private func pageLabel(_ c: Content, long: Bool) -> String {
        let remaining = charactersRemaining(c)
        if long { return remaining < Int(ReadingTime.charactersPerMinute) ? "Under a minute left" : "\(ReadingTime.minutes(remaining)) min left in edition" }
        let pages = "Page \(page + 1) of \(pageCount)"
        if c.kind == .brief, isLastPage { return pages }
        return pages + " · " + ReadingTime.leftLabel(remaining)
    }

    private func charactersRemaining(_ c: Content) -> Int {
        guard layout.ranges.indices.contains(page) else { return c.totalCharacters }
        return max(0, c.text.length - layout.ranges[page].location)
    }

    private func backButton(color: Color, size: CGFloat) -> some View {
        Button { app.route = .today } label: {
            HStack(spacing: 6) {
                IconView(icon: .chevronLeft, size: 16, strokeWidth: 1.6)
                Text("Today").uiText(size)
            }
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .frame(height: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: Controls chrome (04)

    private var barFill: Color {
        palette.id == Tokens.paper.id ? palette.surfaceSunken.color.opacity(0.92) : palette.background.color.opacity(0.92)
    }

    private func controlsHeader(_ c: Content, width: CGFloat) -> some View {
        ZStack {
            HStack(spacing: 14) {
                Color.clear.frame(width: 68, height: 14) // the system traffic lights
                Button { app.route = .today } label: {
                    HStack(spacing: 6) {
                        IconView(icon: .chevronLeft, size: 16, strokeWidth: 1.6)
                        Text("Today").uiText(14)
                    }
                    .foregroundStyle(palette.ink.color)
                    .padding(.horizontal, 10)
                    .frame(height: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                Spacer()
                HStack(spacing: 4) {
                    toolButton("Appearance", active: false) {
                        Text("Aa").displayText(19)
                    } action: { app.route = .appearance }
                    toolButton("Highlight", active: selection != nil) {
                        IconView(icon: .highlight, size: 19, strokeWidth: 1.5)
                    } action: { saveHighlight(c, note: nil) }
                    if case .passage(let part, _) = app.reading {
                        toolButton(part.isBookmarked ? "Remove bookmark" : "Bookmark", active: false) {
                            IconShape(icon: .bookmark)
                                .fill(part.isBookmarked ? palette.ink.color : .clear)
                                .overlay(IconView(icon: .bookmark, size: 19, strokeWidth: 1.5))
                                .frame(width: 19, height: 19)
                        } action: {
                            part.isBookmarked.toggle()
                            try? context.save()
                        }
                    }
                    toolButton("Notebook", active: false) {
                        IconView(icon: .notebook, size: 19, strokeWidth: 1.5)
                    } action: { app.route = .notebook }
                }
            }
            VStack(spacing: 2) {
                Text(c.controlsTitle).displayText(17).foregroundStyle(palette.ink.color)
                Text(c.controlsSubtitle).uiText(12).foregroundStyle(palette.ink2.color)
            }
            .lineLimit(1)
            .frame(maxWidth: width * 0.45)
        }
        .padding(.horizontal, 20)
        .frame(width: width, height: 72)
        .background(barFill)
        .overlay(alignment: .bottom) { Rectangle().fill(palette.rule.color).frame(height: 1) }
        .onHover { hovering in if hovering { showControlsPinned() } }
    }

    private func toolButton<Label: View>(_ name: String, active: Bool, @ViewBuilder label: () -> Label, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            label()
                .foregroundStyle(palette.ink.color)
                .frame(width: 44, height: 44)
                .background(active ? palette.navActive.color : .clear, in: RoundedRectangle(cornerRadius: 10))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(name)
    }

    private func controlsFooter(_ c: Content, width: CGFloat) -> some View {
        HStack(spacing: 24) {
            Text("Page \(page + 1) of \(pageCount)").fixedSize()
            FolioSlider(value: Binding(get: { Double(page) }, set: { page = Int($0.rounded()) }), range: 0...Double(max(1, pageCount - 1)))
                .environment(readingTheme)
                .disabled(pageCount < 2)
                .accessibilityLabel("Position in edition")
            Text(pageLabel(c, long: true)).fixedSize()
            HStack(spacing: 4) {
                sizeButton(smaller: true)
                sizeButton(smaller: false)
            }
            .padding(.leading, 8)
            Button { hideControls() } label: {
                Text("Hide controls").uiText(13, weight: 500).foregroundStyle(palette.ink.color)
                    .padding(.horizontal, 14).frame(height: 40).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .uiText(13)
        .foregroundStyle(palette.ink2.color)
        .padding(.horizontal, 28)
        .frame(width: width, height: 72)
        .background(barFill)
        .overlay(alignment: .top) { Rectangle().fill(palette.rule.color).frame(height: 1) }
        .onHover { hovering in if hovering { showControlsPinned() } }
    }

    private func sizeButton(smaller: Bool) -> some View {
        Button {
            let next = app.prefs.textSize + (smaller ? -1 : 1)
            app.prefs.textSize = min(24, max(16, next))
        } label: {
            Text("A").displayText(smaller ? 14 : 20)
                .foregroundStyle(palette.ink.color)
                .frame(width: 44, height: 40)
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(palette.control.color, lineWidth: 1))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(smaller ? "Smaller text" : "Larger text")
    }

    // MARK: Last page

    @ViewBuilder
    private func trailer(_ c: Content) -> some View {
        switch app.reading {
        case .passage(let part, let edition):
            VStack(spacing: 18) {
                Text("· · ·").displayText(18, tracking: 0.6).foregroundStyle(theme.readingInk3).accessibilityHidden(true)
                Button { app.finishPassage(part, edition: edition) } label: {
                    Text("Finish this edition").uiText(14, weight: 500).foregroundStyle(palette.ink.color)
                        .padding(.horizontal, 20).frame(height: 44)
                        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(palette.rule.color, lineWidth: 1))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.return, modifiers: [])
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 32)
        case .brief(let brief, _):
            VStack(alignment: .leading, spacing: 12) {
                Kicker(text: "Written by AI from these sources", color: .ink2)
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(brief.sources.enumerated()), id: \.offset) { i, s in
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text("\(i + 1).").frame(width: 14, alignment: .trailing)
                            Link(destination: URL(string: s.url) ?? URL(string: "https://en.wikipedia.org")!) {
                                Text("\(s.publisher), “\(s.title).” \(s.year).")
                                    .multilineTextAlignment(.leading)
                            }
                            .foregroundStyle(palette.ink2.color)
                        }
                    }
                }
                .uiText(13, lineHeight: 1.55)
                .foregroundStyle(palette.ink2.color)
                HStack(spacing: 8) {
                    Button(briefFeedback == .deeper ? "Going deeper tomorrow" : "Go deeper tomorrow") { feedback(.deeper, brief: brief) }
                        .buttonStyle(.primaryCompact)
                    Button("More like this") { feedback(.more, brief: brief) }
                        .buttonStyle(SecondaryButtonStyle(height: 40, horizontalPadding: 14, fontSize: 13, weight: 400))
                        .opacity(briefFeedback == .less ? 0.5 : 1)
                    Button("Less like this") { feedback(.less, brief: brief) }
                        .buttonStyle(.quiet)
                        .opacity(briefFeedback == .more ? 0.5 : 1)
                }
                .padding(.top, 6)
            }
            .environment(readingTheme)
            .padding(.top, 16)
            .overlay(alignment: .top) { Rectangle().fill(palette.rule.color).frame(height: 1) }
            .padding(.top, 26)
        case nil:
            EmptyView()
        }
    }

    private func feedback(_ kind: BriefFeedback, brief: Brief) {
        let label = brief.topicLabel
        guard let topic = app.library.topics().first(where: { $0.label == label }) else { briefFeedback = kind; return }
        switch kind {
        case .deeper: topic.deeperAngle = brief.title
        case .more: topic.weight = min(3, topic.weight + 0.25)
        case .less: topic.weight = max(0, topic.weight - 0.25)
        }
        app.library.save()
        briefFeedback = kind
    }

    // MARK: Paging & input

    private func turn(_ delta: Int) {
        let next = min(max(page + delta, 0), pageCount - 1)
        if next != page { page = next }
    }

    private func installMonitor() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .scrollWheel, .swipe]) { event in
            guard app.route == .reader || app.route == .brief, event.window?.title == "Folio" else { return event }
            // Typing in the Ask field or elsewhere isn't a page turn.
            if let responder = event.window?.firstResponder as? NSText, responder.isFieldEditor { return event }
            switch event.type {
            case .keyDown:
                if event.modifierFlags.contains(.command) {
                    if event.charactersIgnoringModifiers == "/" { toggleControls(); return nil }
                    return event
                }
                switch event.keyCode {
                case 123: turn(-1); return nil // ←
                case 124, 49: turn(1); return nil // →, space
                case 53: // esc
                    if selection != nil { closeExplain() } else { app.route = .today }
                    return nil
                default: return event
                }
            case .swipe:
                if event.deltaX > 0 { turn(-1) } else if event.deltaX < 0 { turn(1) }
                return nil
            case .scrollWheel:
                guard event.hasPreciseScrollingDeltas, event.momentumPhase == [] else { return event }
                if event.phase == .began { swipeX = 0 }
                if abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY) { swipeX += event.scrollingDeltaX }
                if event.phase == .ended {
                    if swipeX < -40 { turn(1) } else if swipeX > 40 { turn(-1) }
                    swipeX = 0
                }
                return event
            default:
                return event
            }
        }
    }

    private func showControls() {
        guard !app.readerControlsVisible else { scheduleHide(); return }
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) { app.readerControlsVisible = true }
        scheduleHide()
    }

    private func showControlsPinned() {
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) { app.readerControlsVisible = true }
        scheduleHide()
    }

    private func toggleControls() {
        if app.readerControlsVisible { hideControls() } else { showControlsPinned() }
    }

    private func scheduleHide() {
        hideTask?.cancel()
        hideTask = Task {
            try? await Task.sleep(for: .seconds(2.5))
            guard !Task.isCancelled, selection == nil else { return }
            hideControls()
        }
    }

    private func hideControls() {
        hideTask?.cancel()
        withAnimation(reduceMotion ? nil : .easeIn(duration: 0.35)) { app.readerControlsVisible = false }
    }

    // MARK: Highlights

    private func highlightRanges(_ c: Content) -> [NSRange] {
        guard let id = c.sourceID else { return [] }
        return highlights.filter { $0.workID == id && $0.partIndex == c.partIndex }
            .map { NSRange(location: $0.rangeLocation + c.bodyOffset, length: $0.rangeLength) }
            .filter { NSMaxRange($0) <= c.text.length }
    }

    private func saveHighlight(_ c: Content, note: String?) {
        guard let selection else { return }
        let text = (c.text.string as NSString).substring(with: selection.range).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        let range = NSRange(location: max(0, selection.range.location - c.bodyOffset), length: selection.range.length)
        context.insert(Highlight(text: text, kind: c.kind, sourceTitle: c.sourceTitle, sourceDetail: c.sourceDetail,
                                 workID: c.sourceID, partIndex: c.partIndex, range: range, note: note))
        try? context.save()
        closeExplain()
    }

    // MARK: Explain (04)

    private func select(_ range: NSRange, rect: CGRect, content c: Content) {
        let new = Selection(range: range, rect: rect)
        guard new != selection else { return }
        selection = new
        question = ""
        showControlsPinned()
        runExplain(c)
    }

    private func closeExplain() {
        aiTask?.cancel()
        selection = nil
        answer = ""
        footnote = nil
        question = ""
    }

    private func runExplain(_ c: Content) {
        guard let selection else { return }
        let string = c.text.string as NSString
        let selected = string.substring(with: selection.range)
        let paragraph = string.substring(with: string.paragraphRange(for: selection.range))
        stream(Prompts.explain(explainMode, selection: selected, paragraph: paragraph, work: c.workContext))
    }

    private func runAsk(_ c: Content) {
        let q = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return }
        stream(Prompts.ask(q, passage: c.plainText, work: c.workContext))
    }

    private func stream(_ request: AIRequest) {
        aiTask?.cancel()
        answer = ""
        footnote = nil
        aiTask = Task {
            guard let provider = await app.ai.availableProvider(for: .explain) else {
                answer = app.ai.isEnabled(.explain)
                    ? "The AI provider isn’t reachable right now."
                    : "Explain needs an AI provider. Choose one in Folio › Settings › AI — Apple’s on-device model and Ollama keep everything on this Mac."
                return
            }
            do {
                for try await chunk in provider.stream(request) {
                    if Task.isCancelled { return }
                    answer += chunk
                }
            } catch {
                if !Task.isCancelled { answer = (error as? LocalizedError)?.errorDescription ?? "Something went wrong." }
            }
        }
    }

    private func explainPopover(_ c: Content, selection: Selection, columnX: CGFloat, size: CGSize) -> some View {
        let width: CGFloat = 500
        let midX = columnX + selection.rect.midX
        let x = min(max(midX - 218, columnX - 60), min(columnX + Tokens.Reader.measure + 60, size.width - 16) - width)
        let y = c.top + selection.rect.maxY + 10
        return ExplainPopover(
            mode: Binding(get: { explainMode }, set: { explainMode = $0; runExplain(c) }),
            answer: answer.isEmpty ? "…" : answer,
            footnote: footnote,
            question: $question,
            arrowX: min(max(midX - x, 24), width - 24),
            onAsk: { runAsk(c) },
            onSaveNote: {
                let note = [question.trimmingCharacters(in: .whitespacesAndNewlines), answer].filter { !$0.isEmpty }.joined(separator: " — ")
                saveHighlight(c, note: note.isEmpty ? nil : note)
            }
        )
        .environment(readingTheme)
        .offset(x: x, y: min(y, size.height - 330))
        .transition(.opacity)
    }

    // MARK: "Previously"

    private var recapKey: String {
        if case .passage(let part, _) = app.reading { return "\(part.persistentModelID.hashValue)-\(part.recap == nil)" }
        return "none"
    }

    private func loadRecap() async {
        guard case .passage(let part, _) = app.reading, part.index > 0, part.recap == nil,
              let work = part.work, let previous = work.part(at: part.index - 1),
              let provider = await app.ai.availableProvider(for: .recap) else { return }
        let request = Prompts.recap(previousPart: previous.text, work: .init(title: work.title, author: work.author, chapter: previous.chapterTitle))
        guard let text = try? await provider.complete(request), !Task.isCancelled else { return }
        part.recap = Prompts.clampRecap(text)
        try? context.save()
    }
}
