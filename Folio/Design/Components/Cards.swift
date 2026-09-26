import SwiftUI

/// The small pill on an edition cover ("Morning edition · 07:00").
struct EditionBadge: Sendable {
    enum Kind: Sendable {
        /// Ready: an accent dot and ink text.
        case ready
        /// Upcoming: a clock and ink2 text.
        case upcoming
    }

    var text: String
    var kind: Kind
}

/// Today's edition card (Main.dc.html): a 184 pt wash cover with a badge, then kicker, title, meta and actions.
struct EditionCard<Actions: View>: View {
    @Environment(Theme.self) private var theme
    var washes: [WashLayer]
    var badge: EditionBadge
    var kicker: String
    var title: String
    var meta: String
    @ViewBuilder var actions: Actions

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Tokens.Radius.card)
        // CSS content-box: the 1 pt border sits outside the content, so everything is inset by 1.
        VStack(alignment: .leading, spacing: 0) {
            WashCover(layers: washes)
                .frame(height: 184)
                .overlay(alignment: .topLeading) {
                    badgeView.padding(.leading, 24).padding(.top, 20)
                }
            VStack(alignment: .leading, spacing: 8) {
                Kicker(text: kicker)
                CSSText(title, style: Tokens.cardTitle)
                    .accessibilityAddTraits(.isHeader)
                Text(meta).uiText(14).foregroundStyle(theme.ink2)
                HStack(spacing: 12) { actions }
                    .padding(.top, 12)
            }
            .padding(.top, 22)
            .padding(.horizontal, Tokens.Spacing.cardPadding)
            .padding(.bottom, Tokens.Spacing.cardPadding)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .clipShape(RoundedRectangle(cornerRadius: Tokens.Radius.card - 1))
        .padding(1)
        .background(theme.surface, in: shape)
        .overlay(shape.strokeBorder(theme.rule, lineWidth: 1))
        .accessibilityElement(children: .contain)
    }

    private var badgeView: some View {
        HStack(spacing: 8) {
            switch badge.kind {
            case .ready:
                Circle().fill(theme.accentColor).frame(width: 6, height: 6)
            case .upcoming:
                IconView(icon: .schedule, size: 12, strokeWidth: 2)
            }
            Text(badge.text).uiText(12, weight: 500)
        }
        .foregroundStyle(badge.kind == .ready ? theme.ink : theme.ink2)
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
        .background(theme.surface.opacity(0.86), in: Capsule(style: .circular))
    }
}

/// A resurfaced highlight (Main.dc.html "Back from four days ago"): icon, kicker, italic quote, source, actions.
struct QuoteCard<Actions: View>: View {
    @Environment(Theme.self) private var theme
    var kicker: String
    var quote: String
    var source: String
    @ViewBuilder var actions: Actions

    var body: some View {
        HStack(spacing: 28) {
            IconView(icon: .resurface, size: 28, strokeWidth: 1.4)
                .foregroundStyle(theme.accentColor)
            VStack(alignment: .leading, spacing: 6) {
                Kicker(text: kicker)
                Text(quote)
                    .textStyle(Tokens.quote)
                    .foregroundStyle(theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Text(source).uiText(13).foregroundStyle(theme.ink2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 8) { actions }
        }
        .padding(.vertical, 24)
        .padding(.horizontal, 28)
        .background(theme.surfaceSunken, in: RoundedRectangle(cornerRadius: Tokens.Radius.card))
    }
}
