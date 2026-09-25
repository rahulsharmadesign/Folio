import AppKit
import SwiftUI

/// Paged, non-scrolling text (SPEC › Reader): one `NSLayoutManager` flowing into a run of fixed
/// `NSTextContainer`s, one per page. Only the current page's `NSTextView` is on screen.
/// M1 adds input (keys, swipe, edge zones), selection → Explain, and the highlight marker.
struct PagedReader: NSViewRepresentable {
    var text: NSAttributedString
    /// Page size in points; width is the 620 pt measure.
    var pageSize: CGSize
    var page: Int
    var onLayout: (_ pageCount: Int) -> Void = { _ in }

    func makeCoordinator() -> Paginator { Paginator() }

    func makeNSView(context: Context) -> NSView {
        let host = FlippedView()
        host.wantsLayer = true
        return host
    }

    func updateNSView(_ host: NSView, context: Context) {
        let paginator = context.coordinator
        if paginator.needsLayout(text: text, pageSize: pageSize) {
            let count = paginator.layout(text: text, pageSize: pageSize)
            let report = onLayout
            Task { @MainActor in report(count) }
        }
        paginator.show(page: page, in: host)
    }

    @MainActor
    final class Paginator {
        private let storage = NSTextStorage()
        private let layoutManager = NSLayoutManager()
        private var views: [NSTextView] = []
        private var laidOutText: NSAttributedString?
        private var laidOutSize: CGSize = .zero

        init() {
            storage.addLayoutManager(layoutManager)
            layoutManager.allowsNonContiguousLayout = false
        }

        var pageCount: Int { views.count }

        func needsLayout(text: NSAttributedString, pageSize: CGSize) -> Bool {
            laidOutSize != pageSize || laidOutText.map { !$0.isEqual(to: text) } ?? true
        }

        /// Flows the text into as many page containers as it needs. Returns the page count.
        @discardableResult
        func layout(text: NSAttributedString, pageSize: CGSize) -> Int {
            views.forEach { $0.removeFromSuperview() }
            views.removeAll()
            while !layoutManager.textContainers.isEmpty { layoutManager.removeTextContainer(at: 0) }
            storage.setAttributedString(text)
            laidOutText = text
            laidOutSize = pageSize
            guard pageSize.width > 0, pageSize.height > 0 else { return 0 }

            let totalGlyphs = layoutManager.numberOfGlyphs
            var laidOut = 0
            repeat {
                let container = NSTextContainer(size: pageSize)
                container.lineFragmentPadding = 0
                layoutManager.addTextContainer(container)
                let range = layoutManager.glyphRange(for: container)
                let view = NSTextView(frame: CGRect(origin: .zero, size: pageSize), textContainer: container)
                view.isEditable = false
                view.isSelectable = true
                view.drawsBackground = false
                view.textContainerInset = .zero
                view.isVerticallyResizable = false
                view.isHorizontallyResizable = false
                views.append(view)
                if range.length == 0 { break } // Nothing fits (e.g. a zero-height page): stop rather than loop.
                laidOut = NSMaxRange(range)
            } while laidOut < totalGlyphs
            return views.count
        }

        func show(page: Int, in host: NSView) {
            guard !views.isEmpty else { host.subviews.forEach { $0.removeFromSuperview() }; return }
            let view = views[min(max(page, 0), views.count - 1)]
            guard view.superview !== host else { return }
            host.subviews.forEach { $0.removeFromSuperview() }
            host.addSubview(view)
        }

        /// The character range on a page (for "Previously" placement, highlights and progress).
        func characterRange(ofPage page: Int) -> NSRange? {
            guard views.indices.contains(page), let container = views[page].textContainer else { return nil }
            let glyphs = layoutManager.glyphRange(for: container)
            return layoutManager.characterRange(forGlyphRange: glyphs, actualGlyphRange: nil)
        }
    }

    private final class FlippedView: NSView {
        override var isFlipped: Bool { true }
    }
}
