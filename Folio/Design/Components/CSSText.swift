import AppKit
import SwiftUI

/// Multi-line text that wraps like the CSS source: greedy line breaking (SwiftUI's `Text` moves a word
/// down to avoid a one-word last line, which the designs don't do) and CSS line boxes
/// (`line-height × size`, half-leading above and below). Use it for wrapping headings and paragraphs
/// whose line breaks must match the renders.
struct CSSText: View {
    @Environment(Theme.self) private var theme
    let text: String
    let style: TypeStyle
    var color: Color?

    init(_ text: String, style: TypeStyle, color: Color? = nil) {
        self.text = text
        self.style = style
        self.color = color
    }

    var body: some View {
        let font = Fonts.nsFont(family: theme.family(for: style.role), size: style.size, weight: style.weight, italic: style.italic)
        let ink = color ?? style.color.map { theme.ink($0) } ?? theme.ink
        CSSTextView(string: Self.attributed(text, style: style, font: font, color: NSColor(ink)),
                    cssBaseline: Self.halfLeading(style: style, font: font) + font.ascender)
            .accessibilityElement()
            .accessibilityLabel(Text(text))
    }

    static func attributed(_ text: String, style: TypeStyle, font: NSFont, color: NSColor) -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byWordWrapping
        paragraph.lineBreakStrategy = []
        if let lh = style.lineHeight {
            paragraph.minimumLineHeight = lh * style.size
            paragraph.maximumLineHeight = lh * style.size
        }
        return NSAttributedString(string: style.uppercase ? text.uppercased() : text, attributes: [
            .font: font,
            .foregroundColor: color,
            .kern: style.tracking * style.size,
            .paragraphStyle: paragraph,
        ])
    }

    /// CSS splits a line box's extra space half above, half below the glyphs.
    static func halfLeading(style: TypeStyle, font: NSFont) -> CGFloat {
        guard let lh = style.lineHeight else { return 0 }
        return (lh * style.size - (font.ascender - font.descender)) / 2
    }
}

private struct CSSTextView: NSViewRepresentable {
    let string: NSAttributedString
    /// Where CSS puts the first baseline, from the top of the box (half-leading + ascent).
    let cssBaseline: CGFloat

    func makeNSView(context: Context) -> DrawingView { DrawingView() }

    func updateNSView(_ view: DrawingView, context: Context) {
        if !view.string.isEqual(to: string) || view.cssBaseline != cssBaseline {
            view.string = string
            view.cssBaseline = cssBaseline
            view.needsDisplay = true
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView view: DrawingView, context: Context) -> CGSize? {
        let layout = TextLayout(string: string, width: proposal.width ?? .greatestFiniteMagnitude)
        return CGSize(width: proposal.width ?? layout.usedRect.width, height: layout.usedRect.height)
    }

    /// One TextKit 1 stack, laid out at a width.
    @MainActor
    struct TextLayout {
        let manager = NSLayoutManager()
        let container: NSTextContainer
        let storage: NSTextStorage

        init(string: NSAttributedString, width: CGFloat) {
            storage = NSTextStorage(attributedString: string)
            container = NSTextContainer(size: CGSize(width: width, height: .greatestFiniteMagnitude))
            container.lineFragmentPadding = 0
            manager.addTextContainer(container)
            storage.addLayoutManager(manager)
            manager.ensureLayout(for: container)
        }

        var usedRect: CGRect { manager.usedRect(for: container) }

        /// TextKit's first baseline, from the top.
        var firstBaseline: CGFloat {
            guard manager.numberOfGlyphs > 0 else { return 0 }
            let fragment = manager.lineFragmentRect(forGlyphAt: 0, effectiveRange: nil)
            return fragment.minY + manager.location(forGlyphAt: 0).y
        }
    }

    /// Draws with font smoothing off, so strokes weigh the same as SwiftUI `Text` beside it.
    final class DrawingView: NSView {
        var string = NSAttributedString()
        var cssBaseline: CGFloat = 0
        override var isFlipped: Bool { true }

        override func draw(_ dirtyRect: NSRect) {
            NSGraphicsContext.current?.cgContext.setShouldSmoothFonts(false)
            let layout = TextLayout(string: string, width: bounds.width)
            // Move every line so the first baseline sits where CSS puts it; line pitch is already CSS's.
            let dy = cssBaseline - layout.firstBaseline
            let range = layout.manager.glyphRange(for: layout.container)
            layout.manager.drawGlyphs(forGlyphRange: range, at: CGPoint(x: 0, y: dy))
        }
    }
}
