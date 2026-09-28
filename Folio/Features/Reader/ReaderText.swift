import AppKit

/// Builds the reader's attributed text from a part or a Brief, with the source's type values
/// (Reader.dc.html, Brief.dc.html): CSS line heights, paragraph gaps, 1.4em indents, small-caps openings.
@MainActor
enum ReaderText {
    struct Style {
        var readingFamily: String
        var displayFamily: String
        var uiFamily: String
        var size: CGFloat
        var ink: NSColor
        var ink2: NSColor
    }

    // MARK: Passage (03)

    /// A run of consecutive parts of a book, one after another. `recap` shows as "Previously" on page 1;
    /// the small-caps opening only where a chapter starts. Returns where each part's text starts.
    static func book(_ parts: [String], recap: String?, chapterStart: Bool, style: Style) -> (text: NSAttributedString, starts: [Int]) {
        let out = NSMutableAttributedString()
        if let recap, !recap.isEmpty { out.append(previously(recap, style: style)) }
        var starts: [Int] = []
        for (i, text) in parts.enumerated() {
            if i > 0, out.length > 0 {
                // End the previous part's last paragraph, keeping its paragraph style (and gap).
                out.append(NSAttributedString(string: "\n", attributes: out.attributes(at: out.length - 1, effectiveRange: nil)))
            }
            starts.append(out.length)
            out.append(body(text, style: style, lineHeight: 1.66, gapEm: 0.9, smallCapsOpening: i == 0 && chapterStart, indentFirst: i > 0))
        }
        return (out, starts)
    }

    /// CSS half-leading for the body line box: draw this much higher so glyphs sit where CSS puts them.
    static func cssShift(style: Style, lineHeight: CGFloat) -> CGFloat {
        let font = Fonts.nsFont(family: style.readingFamily, size: style.size)
        return max(0, (lineHeight * style.size - (font.ascender - font.descender)) / 2)
    }

    private static func previously(_ recap: String, style: Style) -> NSAttributedString {
        let label = "Previously".uppercased()
        let labelFont = Fonts.nsFont(family: style.uiFamily, size: 11, weight: 500)
        let textFont = Fonts.nsFont(family: style.uiFamily, size: 13)
        let labelWidth = (label as NSString).size(withAttributes: [.font: labelFont, .kern: 0.66]).width
        let p = NSMutableParagraphStyle()
        p.minimumLineHeight = 19.5
        p.maximumLineHeight = 19.5
        p.tabStops = [NSTextTab(textAlignment: .left, location: ceil(labelWidth) + 10)]
        p.headIndent = ceil(labelWidth) + 10
        p.paragraphSpacing = 10 + 18
        p.lineBreakStrategy = []
        let s = NSMutableAttributedString(string: label, attributes: [.font: labelFont, .kern: 0.66, .foregroundColor: style.ink2, .paragraphStyle: p])
        s.append(NSAttributedString(string: "\t" + recap + "\n", attributes: [.font: textFont, .foregroundColor: style.ink2, .paragraphStyle: p]))
        return s
    }

    /// Body paragraphs: the first unindented (with an optional small-caps opening), the rest indented 1.4em.
    static func body(_ text: String, style: Style, lineHeight: CGFloat, gapEm: CGFloat, smallCapsOpening: Bool, italicMarkup: Bool = false,
                     indentFirst: Bool = false) -> NSAttributedString {
        let paragraphs = smartQuotes(text).components(separatedBy: "\n\n").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        let out = NSMutableAttributedString()
        let font = Fonts.nsFont(family: style.readingFamily, size: style.size)
        let italic = Fonts.nsFont(family: style.readingFamily, size: style.size, italic: true)
        for (i, paragraph) in paragraphs.enumerated() {
            let p = NSMutableParagraphStyle()
            p.minimumLineHeight = lineHeight * style.size
            p.maximumLineHeight = lineHeight * style.size
            p.paragraphSpacing = gapEm * style.size
            p.firstLineHeadIndent = i == 0 && !indentFirst ? 0 : 1.4 * style.size
            p.lineBreakStrategy = []
            p.hyphenationFactor = 0.2
            let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: style.ink, .paragraphStyle: p]
            let line = paragraph + (i == paragraphs.count - 1 ? "" : "\n")
            let piece = italicMarkup ? markup(line, attrs: attrs, italic: italic) : NSMutableAttributedString(string: line, attributes: attrs)
            if i == 0, smallCapsOpening { applySmallCaps(piece, style: style) }
            out.append(piece)
        }
        return out
    }

    /// "I WENT TO THE WOODS because…": the opening words (up to five, stopping at punctuation) in
    /// capitals at 0.82em with 0.07em tracking.
    private static func applySmallCaps(_ s: NSMutableAttributedString, style: Style) {
        let string = s.string as NSString
        var end = 0
        var words = 0
        var inWord = false
        for i in 0..<min(string.length, 80) {
            let c = Character(UnicodeScalar(string.character(at: i)) ?? " ")
            if !inWord, words == 0, "“‘\"'(".contains(c) { end = i + 1; continue } // an opening quote
            if c.isLetter || c == "’" || c == "'" {
                if !inWord { words += 1; inWord = true }
                end = i + 1
            } else if c == " " {
                inWord = false
                if words >= 5 { break }
            } else {
                break
            }
        }
        guard end > 0 else { return }
        let range = NSRange(location: 0, length: end)
        let caps = string.substring(with: range).uppercased()
        let small = Fonts.nsFont(family: style.readingFamily, size: style.size * 0.82)
        let attrs = s.attributes(at: 0, effectiveRange: nil)
        var capsAttrs = attrs
        capsAttrs[.font] = small
        capsAttrs[.kern] = 0.07 * style.size * 0.82
        s.replaceCharacters(in: range, with: NSAttributedString(string: caps, attributes: capsAttrs))
    }

    /// Typographer's quotes for display ("…" → “…”, ' → ’). One character for one, so ranges still line up.
    static func smartQuotes(_ text: String) -> String {
        var out = ""
        out.reserveCapacity(text.count)
        var previous: Character = " "
        for c in text {
            let opening = previous.isWhitespace || "([{—–-".contains(previous)
            switch c {
            case "\"": out.append(opening ? "“" : "”")
            case "'": out.append(opening ? "‘" : "’")
            default: out.append(c)
            }
            previous = c
        }
        return out
    }

    /// `*word*` → italic.
    static func markup(_ text: String, attrs: [NSAttributedString.Key: Any], italic: NSFont) -> NSMutableAttributedString {
        let out = NSMutableAttributedString()
        var italicOn = false
        for (i, piece) in text.components(separatedBy: "*").enumerated() {
            if i > 0 { italicOn.toggle() }
            var a = attrs
            if italicOn { a[.font] = italic }
            out.append(NSAttributedString(string: piece, attributes: a))
        }
        return out
    }

    // MARK: Brief (06)

    static func brief(kicker: String, title: String, standfirst: String, body text: String, style: Style) -> NSAttributedString {
        let out = NSMutableAttributedString()

        let k = NSMutableParagraphStyle()
        k.paragraphSpacing = 10
        k.minimumLineHeight = 16
        k.maximumLineHeight = 16
        out.append(NSAttributedString(string: kicker.uppercased() + "\n", attributes: [
            .font: Fonts.nsFont(family: style.uiFamily, size: 12, weight: 500), .kern: 0.96, .foregroundColor: style.ink2, .paragraphStyle: k,
        ]))

        let t = NSMutableParagraphStyle()
        t.minimumLineHeight = 42 * 1.08
        t.maximumLineHeight = 42 * 1.08
        t.paragraphSpacing = 10
        t.lineBreakStrategy = []
        out.append(NSAttributedString(string: title + "\n", attributes: [
            .font: Fonts.nsFont(family: style.displayFamily, size: 42), .kern: -0.84, .foregroundColor: style.ink, .paragraphStyle: t,
        ]))

        if !standfirst.isEmpty {
            let sf = NSMutableParagraphStyle()
            sf.minimumLineHeight = 19 * 1.45
            sf.maximumLineHeight = 19 * 1.45
            sf.paragraphSpacing = 8 + 16
            out.append(NSAttributedString(string: standfirst + "\n", attributes: [
                .font: Fonts.nsFont(family: style.displayFamily, size: 19, italic: true), .foregroundColor: style.ink2, .paragraphStyle: sf,
            ]))
        }
        out.append(body(text, style: style, lineHeight: 1.6, gapEm: 16.0 / 19.0, smallCapsOpening: false, italicMarkup: true))
        return out
    }
}
