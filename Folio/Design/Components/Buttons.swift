import SwiftUI

/// Ink-filled button: 44 pt, radius 10, 14/500 (Main.dc.html "Begin reading", Library "Add a book or feed").
struct PrimaryButtonStyle: ButtonStyle {
    var height: CGFloat = 44
    var horizontalPadding: CGFloat = 20
    var fontSize: CGFloat = 14

    func makeBody(configuration: Configuration) -> some View {
        PrimaryButtonBody(configuration: configuration, height: height, horizontalPadding: horizontalPadding, fontSize: fontSize)
    }

    private struct PrimaryButtonBody: View {
        @Environment(Theme.self) private var theme
        let configuration: Configuration
        let height: CGFloat
        let horizontalPadding: CGFloat
        let fontSize: CGFloat

        var body: some View {
            configuration.label
                .uiText(fontSize, weight: 500)
                .foregroundStyle(theme.primaryForeground)
                .padding(.horizontal, horizontalPadding)
                .frame(height: height)
                .background(theme.primaryBackground, in: RoundedRectangle(cornerRadius: Tokens.Radius.control))
                .opacity(configuration.isPressed ? 0.85 : 1)
                .contentShape(RoundedRectangle(cornerRadius: Tokens.Radius.control))
        }
    }
}

/// Outlined button: 1 pt `control` border, radius 10 (Main.dc.html "Arrives tonight · peek").
/// That one is an `<a>` (CSS content-box), so the border adds to its 44 × (text + 36) box: 46 pt tall.
/// `<button>`s are border-box, so the compact variants keep their stated height.
struct SecondaryButtonStyle: ButtonStyle {
    var height: CGFloat = 46
    var horizontalPadding: CGFloat = 19
    var fontSize: CGFloat = 14
    var weight: CGFloat = 500
    /// Draw the border (the quiet "Let it go" variant has none and uses ink2).
    var bordered = true

    func makeBody(configuration: Configuration) -> some View {
        SecondaryButtonBody(configuration: configuration, style: self)
    }

    private struct SecondaryButtonBody: View {
        @Environment(Theme.self) private var theme
        let configuration: Configuration
        let style: SecondaryButtonStyle

        var body: some View {
            let shape = RoundedRectangle(cornerRadius: Tokens.Radius.control)
            configuration.label
                .uiText(style.fontSize, weight: style.weight)
                .foregroundStyle(style.bordered ? theme.ink : theme.ink2)
                .padding(.horizontal, style.horizontalPadding)
                .frame(height: style.height)
                .overlay { if style.bordered { shape.strokeBorder(theme.control, lineWidth: 1) } }
                .background(configuration.isPressed ? theme.navActive.opacity(0.5) : .clear, in: shape)
                .contentShape(shape)
        }
    }
}

extension ButtonStyle where Self == PrimaryButtonStyle {
    static var primary: PrimaryButtonStyle { PrimaryButtonStyle() }
    /// 40 pt, 13 pt text (Notebook's recall card).
    static var primaryCompact: PrimaryButtonStyle { PrimaryButtonStyle(height: 40, horizontalPadding: 16, fontSize: 13) }
}

extension ButtonStyle where Self == SecondaryButtonStyle {
    static var secondary: SecondaryButtonStyle { SecondaryButtonStyle() }
    /// 40 pt, 13 pt regular (Today's "Keep").
    static var secondaryCompact: SecondaryButtonStyle { SecondaryButtonStyle(height: 40, horizontalPadding: 16, fontSize: 13, weight: 400) }
    /// Borderless ink2, 40 pt, 13 pt (Today's "Let it go").
    static var quiet: SecondaryButtonStyle { SecondaryButtonStyle(height: 40, horizontalPadding: 16, fontSize: 13, weight: 400, bordered: false) }
}

/// A label with an optional trailing icon, spaced like the source (gap 8, 16 pt icon).
struct ButtonLabel: View {
    let title: String
    var leadingIcon: FolioIcon?
    var trailingIcon: FolioIcon?
    var iconSize: CGFloat = 16
    var iconStroke: CGFloat = 1.6

    var body: some View {
        HStack(spacing: 8) {
            if let leadingIcon { IconView(icon: leadingIcon, size: iconSize, strokeWidth: iconStroke) }
            Text(title)
            if let trailingIcon { IconView(icon: trailingIcon, size: iconSize, strokeWidth: iconStroke) }
        }
    }
}
