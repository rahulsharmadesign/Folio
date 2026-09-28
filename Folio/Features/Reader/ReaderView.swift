import SwiftData
import SwiftUI

/// The paged reader for books (03, 03b, 04) and Briefs (06, 06b). Books page straight through: past either
/// end of the laid-out window the reader moves to the next or previous one, saving the position as it goes.
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
    @State private var cache = BookTextCache()

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
        /// Books: the window runs to the end of its chapter (long chapters are split into sections).
        var endsChapter = true
        /// Books: where each part's text starts, in part order.
        var partStarts: [(index: Int, offset: Int)] = []
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
        case .book(let window):
            let work = window.work
            let chapters = cache.chapters(for: work)
            guard let first = work.part(at: window.range.lowerBound) else { return nil }
            let built = cache.window(window, style: style) {
                let parts = window.range.compactMap { work.part(at: $0) }
                let recap = window.showsRecap && first.index > 0 ? first.recap : nil
                let chapterStart = first.index == 0 || chapters[first.index - 1] != first.chapterTitle
                return ReaderText.book(parts.map(\.text), recap: recap, chapterStart: chapterStart, style: style)
            }
            let chapter = first.chapterTitle.isEmpty ? work.title : first.chapterTitle
            let isLastWindow = window.range.upperBound >= work.partCount - 1
            return Content(
                text: built.text, bodyOffset: 0, top: 124, footerHeight: 72,
                runningHead: chapter,
                footerLeft: "\(work.title) · \(work.progressLabel)",
                controlsTitle: work.title,
                controlsSubtitle: "\(chapter) · \(work.progressLabel)",
                trailerReserve: isLastWindow ? 118 : 0,
                cssShift: ReaderText.cssShift(style: style, lineHeight: 1.66),
                totalCharacters: built.text.length,
                sourceID: work.id,
                endsChapter: window.range.upperBound + 1 >= chapters.count || chapters[window.range.upperBound + 1] != first.chapterTitle,
                partStarts: zip(window.range, built.starts).map { ($0, $1) },
                kind: .passage, sourceTitle: work.title, sourceDetail: chapter,
                workContext: .init(title: work.title, author: work.author, chapter: first.chapterTitle),
                plainText: "")
        case .brief(let brief, let edition):
            let body = BriefParagraphs.ensure(brief.body)
            let text = ReaderText.brief(kicker: brief.topicLabel, title: brief.title, standfirst: brief.standfirst, body: body, style: style)
            let bodyLength = ReaderText.body(body, style: style, lineHeight: 1.6, gapEm: 1, smallCapsOpening: false, italicMarkup: true).length
            let slot = edition.flatMap { e in app.prefs.slots.first { $0.id == e.slotID } }
            let n = CGFloat(brief.sources.count)
            return Content(
                text: text, bodyOffset: text.length - bodyLength, top: 108, footerHeight: 64,
                runningHead: "The Brief · \(slot?.editionName ?? SchedulePlanner.editionName(at: brief.createdAt))",
                footerLeft: brief.kind == .topic ? "The Brief · topic: \(brief.topicLabel.lowercased())" : "The Brief · \(brief.kind.label.lowercased())",
                controlsTitle: "The Brief",
                controlsSubtitle: brief.title,
                trailerReserve: 26 + 1 + 16 + 16 + 12 + n * 21 + max(0, n - 1) * 4 + (brief.kind == .topic ? 18 + 40 : 0) + 8,
                cssShift: ReaderText.cssShift(style: style, lineHeight: 1.6),
                totalCharacters: brief.charCount,
                sourceID: brief.id, kind: .brief, sourceTitle: "The Brief", sourceDetail: brief.topicLabel,
                workContext: .init(title: brief.title, author: "", chapter: ""),
                plainText: brief.body)
        case nil:
            return nil
        }
    }

    private var pageCount: Int { max(1, layout.ranges.count) }
    /// `page` can briefly run past the end while a window paged back into is laid out.
    private var shownPage: Int { min(page, pageCount - 1) }
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
                    recordPosition(c)
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
            recordPosition(c)
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
            backButton(color: theme.readingInk3, size: 13, kind: c.kind)
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
            ProgressHairline(progress: Double(shownPage + 1) / Double(pageCount), width: 140, fill: palette.ink2.color)
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
        if long {
            let span = c.kind == .brief ? "edition" : c.endsChapter ? "chapter" : "section"
            return remaining < Int(ReadingTime.charactersPerMinute) ? "Under a minute left" : "\(ReadingTime.minutes(remaining)) min left in \(span)"
        }
        let pages = "Page \(shownPage + 1) of \(pageCount)"
        if c.kind == .brief, isLastPage { return pages }
        return pages + " · " + ReadingTime.leftLabel(remaining)
    }

    private func charactersRemaining(_ c: Content) -> Int {
        guard layout.ranges.indices.contains(shownPage) else { return c.totalCharacters }
        return max(0, c.text.length - layout.ranges[shownPage].location)
    }

    /// Books go back to Library, Briefs to Today.
    private var backRoute: Route { app.reading?.isBrief == false ? .library : .today }

    private func backButton(color: Color, size: CGFloat, kind: HighlightKind) -> some View {
        Button { app.route = backRoute } label: {
            HStack(spacing: 6) {
                IconView(icon: .chevronLeft, size: 16, strokeWidth: 1.6)
                Text(kind == .brief ? "Today" : "Library").uiText(size)
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
                Button { app.route = backRoute } label: {
                    HStack(spacing: 6) {
                        IconView(icon: .chevronLeft, size: 16, strokeWidth: 1.6)
                        Text(c.kind == .brief ? "Today" : "Library").uiText(14)
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
                    if let part = currentPart(c) {
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
            Text("Page \(shownPage + 1) of \(pageCount)").fixedSize()
            FolioSlider(value: Binding(get: { Double(shownPage) }, set: { page = Int($0.rounded()) }), range: 0...Double(max(1, pageCount - 1)))
                .environment(readingTheme)
                .disabled(pageCount < 2)
                .accessibilityLabel(c.kind == .brief ? "Position in edition" : "Position in chapter")
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
        case .book(let window):
            // Only the last window of a book has a trailer.
            VStack(spacing: 18) {
                Text("· · ·").displayText(18, tracking: 0.6).foregroundStyle(theme.readingInk3).accessibilityHidden(true)
                Button { finishBook(window.work) } label: {
                    Text("Finish the book").uiText(14, weight: 500).foregroundStyle(palette.ink.color)
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
                if brief.kind == .topic { topicFeedback(brief) }
            }
            .environment(readingTheme)
            .padding(.top, 16)
            .overlay(alignment: .top) { Rectangle().fill(palette.rule.color).frame(height: 1) }
            .padding(.top, 26)
        case nil:
            EmptyView()
        }
    }

    /// "Go deeper tomorrow" and More/Less steer a topic; other kinds have no topic to steer.
    private func topicFeedback(_ brief: Brief) -> some View {
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

    private func finishBook(_ work: Work) {
        work.nextPartIndex = work.partCount
        work.status = .finished
        work.lastReadAt = .now
        for part in work.parts where part.readAt == nil { part.readAt = .now }
        try? context.save()
        app.route = .library
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
        let next = shownPage + delta
        if next >= 0, next < pageCount {
            page = next
            return
        }
        // Past either end of a book's window: lay out the next or previous one.
        guard case .book(let window) = app.reading, !layout.ranges.isEmpty else { return }
        let chapters = cache.chapters(for: window.work)
        if next < 0, window.range.lowerBound > 0, let range = BookWindows.backward(to: window.range.lowerBound - 1, chapters: chapters) {
            page = .max / 2 // clamped to the last page once laid out
            app.reading = .book(BookWindow(work: window.work, range: range, startsAtEnd: true))
        } else if next >= pageCount, window.range.upperBound + 1 < chapters.count,
                  let range = BookWindows.forward(from: window.range.upperBound + 1, chapters: chapters) {
            page = 0
            app.reading = .book(BookWindow(work: window.work, range: range))
        }
    }

    // MARK: Position

    /// The part the shown page is in.
    private func currentPart(_ c: Content) -> Part? {
        guard case .book(let window) = app.reading else { return nil }
        let location = layout.ranges.indices.contains(shownPage) ? layout.ranges[shownPage].location : 0
        return BookWindows.part(at: location, offsets: c.partStarts).flatMap { window.work.part(at: $0) }
    }

    /// Every page turn saves where the reader is, so the book reopens there.
    private func recordPosition(_ c: Content) {
        guard case .book(let window) = app.reading, !window.work.isFinished, let part = currentPart(c),
              window.range.contains(part.index) else { return }
        let work = window.work
        guard work.nextPartIndex != part.index || work.lastReadAt.map({ Date.now.timeIntervalSince($0) > 60 }) ?? true else { return }
        work.nextPartIndex = part.index
        work.lastReadAt = .now
        for p in window.range.lowerBound..<part.index { if let earlier = work.part(at: p), earlier.readAt == nil { earlier.readAt = .now } }
        try? context.save()
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
                    if selection != nil { closeExplain() } else { app.route = backRoute }
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
        let starts = Dictionary(c.partStarts.map { ($0.index, $0.offset) }, uniquingKeysWith: { a, _ in a })
        return highlights.filter { $0.workID == id }
            .compactMap { h -> NSRange? in
                let base = c.kind == .brief ? (h.partIndex == nil ? c.bodyOffset : nil) : h.partIndex.flatMap { starts[$0] }
                return base.map { NSRange(location: $0 + h.rangeLocation, length: h.rangeLength) }
            }
            .filter { NSMaxRange($0) <= c.text.length }
    }

    private func saveHighlight(_ c: Content, note: String?) {
        guard let selection else { return }
        let text = (c.text.string as NSString).substring(with: selection.range).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        // Books: stored against the part the selection starts in, so it survives the window changing.
        let partIndex = c.kind == .brief ? nil : BookWindows.part(at: selection.range.location, offsets: c.partStarts)
        let base = partIndex.flatMap { i in c.partStarts.first { $0.index == i }?.offset } ?? c.bodyOffset
        let range = NSRange(location: max(0, selection.range.location - base), length: selection.range.length)
        context.insert(Highlight(text: text, kind: c.kind, sourceTitle: c.sourceTitle, sourceDetail: c.sourceDetail,
                                 workID: c.sourceID, partIndex: partIndex, range: range, note: note))
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
        stream(Prompts.ask(q, passage: currentPart(c)?.text ?? c.plainText, work: c.workContext))
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

    private var recapPart: Part? {
        guard case .book(let window) = app.reading, window.showsRecap else { return nil }
        return window.work.part(at: window.range.lowerBound)
    }

    private var recapKey: String {
        recapPart.map { "\($0.persistentModelID.hashValue)-\($0.recap == nil)" } ?? "none"
    }

    private func loadRecap() async {
        guard let part = recapPart, part.index > 0, part.recap == nil,
              let work = part.work, let previous = work.part(at: part.index - 1),
              let provider = await app.ai.availableProvider(for: .recap) else { return }
        let request = Prompts.recap(previousPart: previous.text, work: .init(title: work.title, author: work.author, chapter: previous.chapterTitle))
        guard let text = try? await provider.complete(request), !Task.isCancelled else { return }
        part.recap = Prompts.clampRecap(text)
        try? context.save()
    }
}

/// Books: the laid-out text of the current window and each work's chapter list, built once rather than on
/// every render (the reader re-renders on every mouse move while its controls show).
@MainActor
final class BookTextCache {
    private var textKey = ""
    private var textValue: (text: NSAttributedString, starts: [Int])?
    private var chaptersKey = ""
    private var chaptersValue: [String] = []

    func window(_ window: BookWindow, style: ReaderText.Style, build: () -> (text: NSAttributedString, starts: [Int])) -> (text: NSAttributedString, starts: [Int]) {
        let recap = window.showsRecap ? window.work.part(at: window.range.lowerBound)?.recap ?? "" : ""
        let key = [window.work.id.uuidString, "\(window.range)", recap, style.readingFamily, style.uiFamily, "\(style.size)",
                   style.ink.description, style.ink2.description].joined(separator: "|")
        if key != textKey || textValue == nil {
            textValue = build()
            textKey = key
        }
        return textValue!
    }

    func chapters(for work: Work) -> [String] {
        let key = "\(work.id)-\(work.partCount)"
        if key != chaptersKey {
            chaptersValue = work.sortedParts.map(\.chapterTitle)
            chaptersKey = key
        }
        return chaptersValue
    }
}
