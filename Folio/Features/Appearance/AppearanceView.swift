import SwiftUI

/// Appearance (10, Appearance.dc.html): paper theme, fonts, accent and text size, with a live preview.
/// Changes apply everywhere at once through `Preferences` → `Theme`.
struct AppearanceView: View {
    @Environment(AppState.self) private var app
    @Environment(Theme.self) private var theme

    /// Per-theme swatch wash (Appearance.dc.html script: T).
    private static let washes: [String: (asset: String, opacity: Double)] = [
        "paper": ("wc-ochre", 0.7), "sage": ("wc-sage", 0.75), "mist": ("wc-lapis", 0.7), "dusk": ("wc-plum", 0.35),
    ]
    /// Unselected font-chip border, stated only in the source.
    private static let chipBorder = RGBA(0xDDD3C0).color

    var body: some View {
        @Bindable var app = app
        HStack(alignment: .top, spacing: 48) {
            VStack(alignment: .leading, spacing: 22) {
                ScreenHeader(title: "Appearance", subtitle: "Make the page yours. Changes preview on the right.")

                section("Paper") {
                    HStack(spacing: 12) {
                        ForEach(Tokens.themes) { palette in themeSwatch(palette) }
                    }
                }
                section("Headings") {
                    fontChips(Tokens.displayFamilyOptions, selection: $app.prefs.displayFamily, size: 17)
                }
                section("Reading text") {
                    fontChips(Tokens.readingFamilyOptions, selection: $app.prefs.readingFamily, size: 15)
                }
                section("Interface") {
                    fontChips(Tokens.uiFamilyOptions, selection: $app.prefs.uiFamily, size: 14)
                }
                HStack(alignment: .top, spacing: 24) {
                    section("Accent") {
                        HStack(spacing: 10) {
                            ForEach(Tokens.accents) { accent in
                                let on = accent.id == app.prefs.accentID
                                Button { app.prefs.accentID = accent.id } label: {
                                    Circle().fill(accent.value.color).frame(width: 30, height: 30)
                                        .frame(width: 44, height: 44)
                                        .overlay { if on { Circle().strokeBorder(theme.ink, lineWidth: 1.5) } }
                                        .contentShape(Circle())
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(accent.id.capitalized)
                                .accessibilityAddTraits(on ? .isSelected : [])
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    section("Text size · \(Int(app.prefs.textSize))") {
                        FolioSlider(value: $app.prefs.textSize, range: 16...24)
                            .frame(height: 44)
                            .accessibilityLabel("Text size")
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .frame(width: 488, alignment: .leading)

            VStack(alignment: .leading, spacing: 10) {
                Kicker(text: "Preview", tracking: 0.08)
                preview
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .padding(.top, 56)
        .padding(.leading, 64)
        .padding(.trailing, 56)
        .padding(.bottom, 32)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Kicker(text: title, tracking: 0.08)
            content()
        }
    }

    private func themeSwatch(_ palette: Palette) -> some View {
        let on = palette.id == app.prefs.themeID
        let wash = Self.washes[palette.id] ?? ("wc-ochre", 0.7)
        return Button { app.prefs.themeID = palette.id } label: {
            VStack(alignment: .leading, spacing: 6) {
                ZStack(alignment: .bottomLeading) {
                    palette.background.color
                        .overlay {
                            GeometryReader { _ in
                                Image(wash.asset).resizable().frame(width: 150, height: 107)
                                    .opacity(wash.opacity).blendMode(palette.washBlend.blendMode)
                                    .offset(x: -26, y: -20)
                            }
                        }
                    Text("Aa").displayText(18).foregroundStyle(palette.ink.color).padding(.leading, 10).padding(.bottom, 6)
                }
                .frame(height: 62)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay {
                    if on {
                        // box-shadow: 0 0 0 2px paper, 0 0 0 3.5px ink
                        RoundedRectangle(cornerRadius: 12).strokeBorder(theme.ink, lineWidth: 1.5).padding(-3.5)
                    } else {
                        RoundedRectangle(cornerRadius: 10).strokeBorder(theme.controlSoft, lineWidth: 1)
                    }
                }
                Text(palette.id.capitalized).uiText(13).foregroundStyle(theme.ink)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private func fontChips(_ families: [String], selection: Binding<String>, size: CGFloat) -> some View {
        FlowLayout(spacing: 8) {
            ForEach(families, id: \.self) { family in
                let on = selection.wrappedValue == family
                Button { selection.wrappedValue = family } label: {
                    Text(family)
                        .font(Fonts.font(family: family, size: size))
                        .foregroundStyle(theme.ink)
                        .padding(.horizontal, 14)
                        .frame(height: 40)
                        .background(on ? theme.surface : .clear, in: RoundedRectangle(cornerRadius: 10))
                        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(on ? theme.ink : Self.chipBorder, lineWidth: 1))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
    }

    private var preview: some View {
        let p = theme.reading
        let wash = Self.washes[p.id] ?? ("wc-ochre", 0.7)
        let shape = RoundedRectangle(cornerRadius: 18)
        return ZStack(alignment: .topLeading) {
            p.background.color
            GeometryReader { geo in
                Image(wash.asset).resizable().frame(width: 440, height: 313)
                    .opacity(wash.opacity).blendMode(p.washBlend.blendMode)
                    .offset(x: geo.size.width - 440 + 140, y: -110)
            }
            GrainLayer(opacity: p.grainOpacity)
            VStack(alignment: .leading, spacing: 16) {
                Text("Morning edition · \(app.library.currentWork?.title ?? "Walden")")
                    .textStyle(Tokens.kicker.with(tracking: 0.08))
                    .foregroundStyle(p.ink2.color)
                CSSText("Where I Lived, and What I Lived For", style: TypeStyle(role: .display, size: 34, lineHeight: 1.1, tracking: -0.01), color: p.ink.color)
                CSSText("I went to the woods because I wished to live deliberately, to front only the essential facts of life, and see if I could not learn what it had to teach, and not, when I came to die, discover that I had not lived.",
                        style: TypeStyle(role: .reading, size: CGFloat(app.prefs.textSize), lineHeight: 1.65), color: p.ink.color)
                HStack(spacing: 14) {
                    Text("Begin reading").uiText(14, weight: 500).foregroundStyle(RGBA(0xFBF8F2).color)
                        .padding(.horizontal, 16).frame(height: 40)
                        .background(theme.accentColor, in: RoundedRectangle(cornerRadius: 10))
                    Text("4 min").uiText(13).foregroundStyle(p.ink2.color)
                }
                .padding(.top, 6)
            }
            .padding(.vertical, 40)
            .padding(.horizontal, 36)
        }
        .clipShape(shape)
        .overlay(shape.strokeBorder(p.rule.color, lineWidth: 1))
        .shadow(color: RGBA(0x3C301E, 0.35).color.opacity(0.5), radius: 30, y: 24)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Preview")
    }
}
