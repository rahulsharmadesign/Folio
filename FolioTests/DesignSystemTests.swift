import AppKit
import SwiftUI
import Testing
@testable import Folio

@MainActor
struct FontTests {
    @Test(arguments: Tokens.displayFamilyOptions + Tokens.readingFamilyOptions + Tokens.uiFamilyOptions)
    func everyAppearanceFamilyResolves(family: String) {
        Fonts.register()
        let font = Fonts.nsFont(family: family, size: 20)
        #expect(font.familyName == family)
    }

    @Test func italicsUseTheItalicCut() {
        let font = Fonts.nsFont(family: "Newsreader", size: 28, italic: true)
        #expect(font.fontDescriptor.symbolicTraits.contains(.italic))
    }

    @Test func weightUsesTheVariableAxis() {
        let regular = Fonts.nsFont(family: "Geist", size: 14)
        let medium = Fonts.nsFont(family: "Geist", size: 14, weight: 500)
        let text = "Begin reading" as NSString
        #expect(text.size(withAttributes: [.font: medium]).width > text.size(withAttributes: [.font: regular]).width)
    }
}

struct TokenTests {
    @Test func paperMatchesTheDesign() {
        #expect(Tokens.paper.background == RGBA(0xF6F1E7))
        #expect(Tokens.paper.ink3 == RGBA(0x6E685E))
        #expect(Tokens.highlightFill == RGBA(0x587AA8, 0.24))
        #expect(Tokens.Spacing.sidebarWidth == 232)
    }

    @Test func themesFallBackToPaperForUnstatedKeys() {
        #expect(Tokens.sage.background == RGBA(0xEEF0E3))
        #expect(Tokens.sage.sidebar == Tokens.paper.sidebar)
        #expect(Tokens.dusk.washAsset == "wc-plum")
        #expect(Tokens.dusk.washBlend == .screen)
        #expect(Tokens.paper.washAsset == nil)
    }

    @Test func defaultAccentIsInk() {
        #expect(Tokens.defaultAccentID == "ink")
        #expect(Tokens.accentInk.hover == RGBA(0x243B5C))
    }
}

struct SVGPathTests {
    @Test func arcsBecomeTheRightCurve() {
        // The Today icon's sun: a half circle, centre (12, 18), radius 5, above the line.
        let box = SVGPath.parse("M7 18a5 5 0 0 1 10 0").boundingRect
        #expect(abs(box.minX - 7) < 0.01)
        #expect(abs(box.maxX - 17) < 0.01)
        #expect(abs(box.minY - 13) < 0.05)
        #expect(abs(box.maxY - 18) < 0.01)
    }

    @Test func implicitRepeatsAndRelativeCommands() {
        // "M13 6l6 6-6 6" is two relative line-tos.
        let box = SVGPath.parse("M13 6l6 6-6 6").boundingRect
        #expect(box == CGRect(x: 13, y: 6, width: 6, height: 12))
    }

    @Test(arguments: FolioIcon.allCases)
    func iconsStayInsideTheirViewBox(icon: FolioIcon) {
        let box = icon.path.boundingRect
        #expect(!box.isEmpty)
        #expect(CGRect(x: 0, y: 0, width: 24, height: 24).contains(box))
    }
}

struct GreetingTests {
    private func date(hour: Int) -> Date {
        Calendar.current.date(from: DateComponents(year: 2026, month: 9, day: 26, hour: hour))!
    }

    @Test func greetsByTimeOfDay() {
        #expect(Greeting.greeting(for: date(hour: 7), name: "Rahul") == "Good morning, Rahul.")
        #expect(Greeting.greeting(for: date(hour: 14), name: "Rahul") == "Good afternoon, Rahul.")
        #expect(Greeting.greeting(for: date(hour: 21), name: nil) == "Good evening.")
    }

    @Test func dateLineMatchesTheMockup() {
        #expect(Greeting.dateLine(for: date(hour: 8), locale: Locale(identifier: "en_GB")) == "Saturday 26 September")
    }
}
