import AppKit
import SwiftUI

/// What the reader reports after laying out.
struct PageLayout: Equatable {
    /// Character range of each page.
    var ranges: [NSRange]
    /// Height used on the last page (for placing "Finish this edition" or the Brief's sources).
    var lastPageUsedHeight: CGFloat
}

/// Paged, non-scrolling text (SPEC › Reader): one `NSLayoutManager` flowing into a run of fixed
/// `NSTextContainer`s, one per page, each shown by a selectable, non-editable `NSTextView`.
struct PagedReader: NSViewRepresentable {
    var text: NSAttributedString
    /// Page size in points; width is the 620 pt measure.
    var pageSize: CGSize
    var page: Int
    /// Space the last page must keep free below the text (for a trailer view). Adds a page if needed.
    var lastPageReserve: CGFloat = 0
    /// Draw the text this much higher, so fixed line heights split their leading like CSS.
    var cssShift: CGFloat = 0
    /// Saved highlights, drawn as markers.
    var markers: [NSRange] = []
    var markerColor: NSColor
    var reduceMotion = false
    var onLayout: (PageLayout) -> Void = { _ in }
    /// A selection was made with the mouse: range and its rect in this view's coordinates (top-left origin).
    var onSelect: (NSRange, CGRect) -> Void = { _, _ in }
    var onDeselect: () -> Void = {}

    func makeCoordinator() -> Paginator { Paginator() }

    func makeNSView(context: Context) -> NSView {
        let host = FlippedView()
        host.wantsLayer = true
        return host
    }

    func updateNSView(_ host: NSView, context: Context) {
        let p = context.coordinator
        p.onSelect = onSelect
        p.onDeselect = onDeselect
        p.markerColor = markerColor
        p.cssShift = cssShift
        p.layoutManager.markers = markers
        if p.needsLayout(text: text, pageSize: pageSize, reserve: lastPageReserve) {
            let layout = p.layout(text: text, pageSize: pageSize, reserve: lastPageReserve)
            let report = onLayout
            Task { @MainActor in report(layout) }
        }
        p.show(page: page, in: host, reduceMotion: reduceMotion)
        p.visibleView?.needsDisplay = true
    }

    @MainActor
    final class Paginator: NSObject, NSTextViewDelegate {
        let storage = NSTextStorage()
        let layoutManager = MarkerLayoutManager()
        private var views: [ReaderTextView] = []
        private var laidOutText: NSAttributedString?
        private var laidOutSize: CGSize = .zero
        private var laidOutReserve: CGFloat = -1
        private var shownIndex: Int?
        var onSelect: (NSRange, CGRect) -> Void = { _, _ in }
        var onDeselect: () -> Void = {}
        var markerColor: NSColor = .clear { didSet { layoutManager.markerColor = markerColor } }
        var cssShift: CGFloat = 0

        override init() {
            super.init()
            storage.addLayoutManager(layoutManager)
            layoutManager.allowsNonContiguousLayout = false
        }

        var visibleView: NSView? { shownIndex.flatMap { views.indices.contains($0) ? views[$0] : nil } }

        func needsLayout(text: NSAttributedString, pageSize: CGSize, reserve: CGFloat) -> Bool {
            laidOutSize != pageSize || laidOutReserve != reserve || laidOutText.map { !$0.isEqual(to: text) } ?? true
        }

        func layout(text: NSAttributedString, pageSize: CGSize, reserve: CGFloat) -> PageLayout {
            views.forEach { $0.removeFromSuperview() }
            views.removeAll()
            shownIndex = nil
            while !layoutManager.textContainers.isEmpty { layoutManager.removeTextContainer(at: 0) }
            storage.setAttributedString(text)
            laidOutText = text
            laidOutSize = pageSize
            laidOutReserve = reserve
            guard pageSize.width > 0, pageSize.height > 40 else { return PageLayout(ranges: [], lastPageUsedHeight: 0) }

            let totalGlyphs = layoutManager.numberOfGlyphs
            var laidOut = 0
            repeat {
                let container = NSTextContainer(size: pageSize)
                container.lineFragmentPadding = 0
                layoutManager.addTextContainer(container)
                views.append(makeView(container, size: pageSize))
                let range = layoutManager.glyphRange(for: container)
                if range.length == 0 { break }
                laidOut = NSMaxRange(range)
            } while laidOut < totalGlyphs

            var lastUsed = views.last?.textContainer.map { layoutManager.usedRect(for: $0).height } ?? 0
            if reserve > 0, lastUsed + reserve > pageSize.height {
                // The trailer doesn't fit under the text: give it a page of its own.
                let container = NSTextContainer(size: pageSize)
                container.lineFragmentPadding = 0
                layoutManager.addTextContainer(container)
                views.append(makeView(container, size: pageSize))
                lastUsed = 0
            }
            let ranges = views.map { view -> NSRange in
                guard let c = view.textContainer else { return NSRange(location: 0, length: 0) }
                return layoutManager.characterRange(forGlyphRange: layoutManager.glyphRange(for: c), actualGlyphRange: nil)
            }
            return PageLayout(ranges: ranges, lastPageUsedHeight: lastUsed)
        }

        private func makeView(_ container: NSTextContainer, size: CGSize) -> ReaderTextView {
            let view = ReaderTextView(frame: CGRect(x: 0, y: -cssShift, width: size.width, height: size.height + cssShift), textContainer: container)
            view.isEditable = false
            view.isSelectable = true
            view.drawsBackground = false
            view.textContainerInset = .zero
            view.isVerticallyResizable = false
            view.isHorizontallyResizable = false
            view.isRichText = true
            view.selectedTextAttributes = [:] // The layout manager draws selection as a marker.
            view.linkTextAttributes = [:]
            view.delegate = self
            view.onMouseUp = { [weak self, weak view] in
                guard let self, let view else { return }
                self.selectionEnded(in: view)
            }
            layoutManager.selection = { [weak view] in view?.selectedRange() ?? NSRange(location: 0, length: 0) }
            return view
        }

        func show(page: Int, in host: NSView, reduceMotion: Bool) {
            guard !views.isEmpty else {
                host.subviews.forEach { $0.removeFromSuperview() }
                return
            }
            let index = min(max(page, 0), views.count - 1)
            let view = views[index]
            guard view.superview !== host else { return }
            if let previous = shownIndex, host.layer != nil, previous != index {
                let transition = CATransition()
                transition.duration = reduceMotion ? 0.22 : 0.28
                transition.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                if reduceMotion {
                    transition.type = .fade
                } else {
                    transition.type = .push
                    transition.subtype = index > previous ? .fromRight : .fromLeft
                }
                host.layer?.add(transition, forKey: "page")
            }
            host.subviews.forEach { $0.removeFromSuperview() }
            host.addSubview(view)
            shownIndex = index
            view.setSelectedRange(NSRange(location: view.selectedRange().location, length: 0))
        }

        private func selectionEnded(in view: ReaderTextView) {
            let range = view.selectedRange()
            guard range.length > 0, let container = view.textContainer else {
                onDeselect()
                return
            }
            let glyphs = layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            var rect = layoutManager.boundingRect(forGlyphRange: glyphs, in: container)
            rect.origin.y -= cssShift
            onSelect(range, rect)
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            (notification.object as? NSView)?.needsDisplay = true
            if let view = notification.object as? NSTextView, view.selectedRange().length == 0 { onDeselect() }
        }
    }

    private final class FlippedView: NSView {
        override var isFlipped: Bool { true }
    }
}

/// Text view that reports mouse-up (end of a selection drag) and never shows an insertion point.
final class ReaderTextView: NSTextView {
    var onMouseUp: () -> Void = {}

    override func mouseUp(with event: NSEvent) {
        super.mouseUp(with: event)
        onMouseUp()
    }

    override func mouseDown(with event: NSEvent) {
        super.mouseDown(with: event)
        // NSTextView tracks the drag inside mouseDown; the selection is final when it returns.
        onMouseUp()
    }

    override var acceptsFirstResponder: Bool { true }
    override func drawInsertionPoint(in rect: NSRect, color: NSColor, turnedOn flag: Bool) {}
}

/// Draws highlights and the selection as a marker: a band from 14% to 90% of the line height
/// (tokens: highlight.coverage), not the full line box.
final class MarkerLayoutManager: NSLayoutManager {
    var markers: [NSRange] = []
    var markerColor: NSColor = .clear
    var selection: () -> NSRange = { NSRange(location: 0, length: 0) }

    override func drawBackground(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
        super.drawBackground(forGlyphRange: glyphsToShow, at: origin)
        let selected = selection()
        let ranges = markers + (selected.length > 0 ? [selected] : [])
        guard !ranges.isEmpty else { return }
        markerColor.setFill()
        for range in ranges {
            let glyphs = glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            let visible = NSIntersectionRange(glyphs, glyphsToShow)
            guard visible.length > 0 else { continue }
            enumerateLineFragments(forGlyphRange: visible) { _, usedRect, container, lineRange, _ in
                let piece = NSIntersectionRange(lineRange, visible)
                guard piece.length > 0 else { return }
                let bounds = self.boundingRect(forGlyphRange: piece, in: container)
                let h = usedRect.height
                let band = CGRect(x: bounds.minX + origin.x, y: usedRect.minY + origin.y + h * 0.14,
                                  width: bounds.width, height: h * 0.76)
                NSBezierPath(roundedRect: band, xRadius: 2, yRadius: 2).fill()
            }
        }
    }
}
