import SwiftUI
import Observation

// The types behind the generated `Tokens`, and the live `Theme` every view reads.
// Values come from design/tokens.json via tools/gen-tokens.swift; never hard-code them here.

/// An sRGB colour as the design states it.
struct RGBA: Sendable, Hashable {
    let hex: UInt32
    let alpha: Double

    init(_ hex: UInt32, _ alpha: Double = 1) {
        self.hex = hex
        self.alpha = alpha
    }

    var red: Double { Double((hex >> 16) & 0xFF) / 255 }
    var green: Double { Double((hex >> 8) & 0xFF) / 255 }
    var blue: Double { Double(hex & 0xFF) / 255 }

    var color: Color { Color(.sRGB, red: red, green: green, blue: blue, opacity: alpha) }
    var nsColor: NSColor { NSColor(srgbRed: red, green: green, blue: blue, alpha: alpha) }
}

enum WashBlend: String, Sendable {
    case multiply, screen

    var blendMode: BlendMode { self == .multiply ? .multiply : .screen }
}

struct Palette: Sendable, Identifiable, Hashable {
    let id: String
    let background: RGBA
    let sidebar: RGBA
    let sidebarBorder: RGBA
    let surface: RGBA
    let surfaceSunken: RGBA
    let coverGround: RGBA
    let ink: RGBA
    let ink2: RGBA
    let ink3: RGBA
    let inkOnWash: RGBA
    let rule: RGBA
    let control: RGBA
    let controlSoft: RGBA
    let navActive: RGBA
    let washColor: RGBA
    /// The watercolour a theme tints its reader with (nil for Paper).
    let washAsset: String?
    let washBlend: WashBlend
    let washOpacity: Double
    let grainOpacity: Double
}

struct Accent: Sendable, Identifiable, Hashable {
    let id: String
    let value: RGBA
    let hover: RGBA?
}

enum FontRole: String, Sendable, CaseIterable {
    case display, reading, ui
}

enum InkRole: String, Sendable {
    case ink, ink2, ink3, inkOnWash
}

struct TypeStyle: Sendable {
    var role: FontRole
    var size: CGFloat
    /// CSS line-height as a multiple of the font size.
    var lineHeight: CGFloat? = nil
    /// CSS letter-spacing in em.
    var tracking: CGFloat = 0
    var weight: CGFloat = 400
    var italic: Bool = false
    var uppercase: Bool = false
    var paragraphGap: CGFloat? = nil
    var color: InkRole? = nil
}

/// The app-wide look: theme, accent and font families. Appearance (M5) edits this.
@MainActor @Observable
final class Theme {
    var palette: Palette = Tokens.paper
    var accent: Accent = Tokens.accentInk
    var displayFamily: String = Tokens.displayFamilyDefault
    var readingFamily: String = Tokens.readingFamilyDefault
    var uiFamily: String = Tokens.uiFamilyDefault
    /// Reader body size, 16–24 (tokens: readingBody.userAdjustable).
    var readingSize: CGFloat = Tokens.readingBody.size

    /// Increase Contrast: ink2 wherever ink3 appears (DESIGN.md › Accessibility).
    var increaseContrast = false

    func family(for role: FontRole) -> String {
        switch role {
        case .display: displayFamily
        case .reading: readingFamily
        case .ui: uiFamily
        }
    }

    // Colours views use.
    var background: Color { palette.background.color }
    var sidebar: Color { palette.sidebar.color }
    var sidebarBorder: Color { palette.sidebarBorder.color }
    var surface: Color { palette.surface.color }
    var surfaceSunken: Color { palette.surfaceSunken.color }
    var coverGround: Color { palette.coverGround.color }
    var wash: Color { palette.washColor.color }
    var ink: Color { palette.ink.color }
    var ink2: Color { palette.ink2.color }
    var ink3: Color { (increaseContrast ? palette.ink2 : palette.ink3).color }
    var inkOnWash: Color { palette.inkOnWash.color }
    var rule: Color { palette.rule.color }
    var control: Color { palette.control.color }
    var controlSoft: Color { palette.controlSoft.color }
    var navActive: Color { palette.navActive.color }
    var accentColor: Color { accent.value.color }
    var accentHover: Color { (accent.hover ?? accent.value).color }
    var primaryBackground: Color { Tokens.primaryButtonBackground.color }
    var primaryForeground: Color { Tokens.primaryButtonForeground.color }
    var highlight: Color { Tokens.highlightFill.color }

    func ink(_ role: InkRole) -> Color {
        switch role {
        case .ink: ink
        case .ink2: ink2
        case .ink3: ink3
        case .inkOnWash: inkOnWash
        }
    }
}
