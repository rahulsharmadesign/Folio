import AppKit
import CoreText
import SwiftUI

/// Registers the bundled fonts and resolves the heading (display), reading and interface families.
///
/// The families are variable fonts. Weight is set on the `wght` axis. Optical size is pinned to each
/// font's default: CoreText otherwise applies automatic optical sizing (opsz = point size), which sets
/// Newsreader ~4% wider than the approved renders at display sizes (measured against design/screens).
@MainActor
enum Fonts {
    private struct Face: Sendable {
        let roman: String
        let italic: String?
        /// A separate bold file, for static families.
        let bold: String?
        let hasWeightAxis: Bool
        /// The `opsz` axis default, for families that have one.
        var defaultOpticalSize: CGFloat? = nil
    }

    private static let faces: [String: Face] = [
        "Newsreader": Face(roman: "Newsreader16pt-Regular", italic: "Newsreader16pt-Italic", bold: nil, hasWeightAxis: true, defaultOpticalSize: 18),
        "Literata": Face(roman: "Literata-Regular", italic: "Literata-Italic", bold: nil, hasWeightAxis: true, defaultOpticalSize: 12),
        "Geist": Face(roman: "Geist-Regular", italic: nil, bold: nil, hasWeightAxis: true),
        "Source Serif 4": Face(roman: "SourceSerif4Roman-Regular", italic: "SourceSerif4Italic-Italic", bold: nil, hasWeightAxis: true, defaultOpticalSize: 20),
        "EB Garamond": Face(roman: "EBGaramond-Regular", italic: "EBGaramond-Italic", bold: nil, hasWeightAxis: true),
        "Instrument Serif": Face(roman: "InstrumentSerif-Regular", italic: "InstrumentSerif-Italic", bold: nil, hasWeightAxis: false),
        "Atkinson Hyperlegible": Face(roman: "AtkinsonHyperlegible-Regular", italic: nil, bold: "AtkinsonHyperlegible-Bold", hasWeightAxis: false),
        "Manrope": Face(roman: "Manrope-Regular", italic: nil, bold: nil, hasWeightAxis: true),
        "DM Sans": Face(roman: "DMSans-9ptRegular", italic: nil, bold: nil, hasWeightAxis: true, defaultOpticalSize: 9),
    ]

    static var families: [String] { faces.keys.sorted() }

    private static let weightAxis = 0x7767_6874 // 'wght'
    private static let opticalSizeAxis = 0x6F70_737A // 'opsz'

    /// Info.plist's `ATSApplicationFontsPath` registers the fonts at launch. This is the fallback
    /// (e.g. a test host or a stripped plist): register anything in the bundle's Fonts folder that's missing.
    static func register(bundle: Bundle = .main) {
        guard NSFont(name: "Geist-Regular", size: 12) == nil,
              let dir = bundle.resourceURL?.appendingPathComponent("Fonts"),
              let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
        else { return }
        let urls = files.filter { ["ttf", "otf"].contains($0.pathExtension.lowercased()) }
        CTFontManagerRegisterFontURLs(urls as CFArray, .process, true, nil)
    }

    private struct Key: Hashable {
        let family: String, size: CGFloat, weight: CGFloat, italic: Bool
    }

    private static var cache: [Key: NSFont] = [:]

    /// An AppKit font for the family (falls back to the system font if the family is unknown).
    static func nsFont(family: String, size: CGFloat, weight: CGFloat = 400, italic: Bool = false) -> NSFont {
        let key = Key(family: family, size: size, weight: weight, italic: italic)
        if let hit = cache[key] { return hit }
        let font = makeFont(family: family, size: size, weight: weight, italic: italic)
        cache[key] = font
        return font
    }

    static func font(family: String, size: CGFloat, weight: CGFloat = 400, italic: Bool = false) -> Font {
        Font(nsFont(family: family, size: size, weight: weight, italic: italic) as CTFont)
    }

    private static func makeFont(family: String, size: CGFloat, weight: CGFloat, italic: Bool) -> NSFont {
        guard let face = faces[family] else {
            return .systemFont(ofSize: size, weight: weight >= 600 ? .semibold : weight >= 500 ? .medium : .regular)
        }
        var name = italic ? (face.italic ?? face.roman) : face.roman
        if !face.hasWeightAxis, weight >= 600, let bold = face.bold { name = bold }
        guard let base = NSFont(name: name, size: size) else {
            return .systemFont(ofSize: size)
        }
        var variation: [Int: CGFloat] = [:]
        if face.hasWeightAxis { variation[weightAxis] = weight }
        if let opsz = face.defaultOpticalSize { variation[opticalSizeAxis] = opsz }
        var descriptor = base.fontDescriptor
        if !variation.isEmpty {
            descriptor = descriptor.addingAttributes([.variation: variation])
        }
        if italic, face.italic == nil {
            // No italic cut (Geist, Manrope, DM Sans, Atkinson): slant the roman.
            descriptor = descriptor.addingAttributes([.matrix: AffineTransform(m11: 1, m12: 0, m21: 0.2, m22: 1, tX: 0, tY: 0)])
        }
        return NSFont(descriptor: descriptor, size: size) ?? base
    }
}

// MARK: - Applying a TypeStyle

extension TypeStyle {
    func with(size: CGFloat? = nil, weight: CGFloat? = nil, italic: Bool? = nil, lineHeight: CGFloat? = nil,
              tracking: CGFloat? = nil, color: InkRole? = nil) -> TypeStyle {
        var s = self
        if let size { s.size = size }
        if let weight { s.weight = weight }
        if let italic { s.italic = italic }
        if let lineHeight { s.lineHeight = lineHeight }
        if let tracking { s.tracking = tracking }
        if let color { s.color = color }
        return s
    }
}

/// Font, tracking, case, colour and a CSS-style line box for a `TypeStyle`.
///
/// CSS gives every line `line-height × size`; SwiftUI gives it the font's natural height.
/// The difference is split above and below the text (negative when the CSS box is tighter),
/// and added between lines, so stacked text lands where the design puts it.
struct TypeStyleModifier: ViewModifier {
    @Environment(Theme.self) private var theme
    let style: TypeStyle

    func body(content: Content) -> some View {
        let family = theme.family(for: style.role)
        let ns = Fonts.nsFont(family: family, size: style.size, weight: style.weight, italic: style.italic)
        let natural = ns.ascender - ns.descender + ns.leading
        let target = style.lineHeight.map { $0 * style.size } ?? natural
        let delta = target - natural
        content
            .font(Font(ns as CTFont))
            .tracking(style.tracking * style.size)
            .textCase(style.uppercase ? .uppercase : nil)
            .lineSpacing(max(0, delta))
            .padding(.vertical, delta / 2)
            .modifier(OptionalForeground(color: style.color.map { theme.ink($0) }))
    }
}

private struct OptionalForeground: ViewModifier {
    let color: Color?
    func body(content: Content) -> some View {
        if let color { content.foregroundStyle(color) } else { content }
    }
}

extension View {
    func textStyle(_ style: TypeStyle) -> some View {
        modifier(TypeStyleModifier(style: style))
    }

    /// Interface text (Geist by default) at a size and weight the source states.
    func uiText(_ size: CGFloat, weight: CGFloat = 400, tracking: CGFloat = 0, lineHeight: CGFloat? = nil) -> some View {
        textStyle(TypeStyle(role: .ui, size: size, lineHeight: lineHeight, tracking: tracking, weight: weight))
    }

    /// Display text (Newsreader by default).
    func displayText(_ size: CGFloat, italic: Bool = false, tracking: CGFloat = 0, lineHeight: CGFloat? = nil) -> some View {
        textStyle(TypeStyle(role: .display, size: size, lineHeight: lineHeight, tracking: tracking, italic: italic))
    }

    /// Reading text (Literata by default).
    func readingText(_ size: CGFloat, italic: Bool = false, lineHeight: CGFloat? = nil) -> some View {
        textStyle(TypeStyle(role: .reading, size: size, lineHeight: lineHeight, italic: italic))
    }
}
