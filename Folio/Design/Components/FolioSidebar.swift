import SwiftUI

/// What the sidebar's "Next edition" card shows.
struct NextEditionSummary: Sendable, Equatable {
    /// "Tonight, 21:00"
    var when: String
    /// "The Brief · honeybees"
    var detail: String
}

/// The shared sidebar (Sidebar.dc.html): wordmark, five nav rows and the "Next edition" card.
/// The system traffic lights sit in the 14 pt row at the top; they're positioned by `WindowChrome`, not drawn.
struct FolioSidebar: View {
    @Environment(Theme.self) private var theme
    @Binding var selection: Route
    var nextEdition: NextEditionSummary?
    var onNextEdition: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Color.clear.frame(height: 14) // traffic-light row

            Text("Folio")
                .textStyle(Tokens.wordmark.with(lineHeight: 1, tracking: -0.01))
                .foregroundStyle(theme.ink)
                .padding(.top, 30)
                .padding(.horizontal, 12)
                .padding(.bottom, 26)
                .accessibilityAddTraits(.isHeader)

            VStack(spacing: 2) {
                ForEach(Route.sidebar, id: \.self) { route in
                    NavRow(route: route, isActive: selection == route) { selection = route }
                }
            }

            Spacer(minLength: 0)

            NextEditionCard(summary: nextEdition, action: onNextEdition)
        }
        .padding(.top, 18)
        .padding(.leading, 12)
        .padding(.trailing, 12 + 1) // border-box: the 1 pt right border is inside the 232
        .padding(.bottom, 18)
        .frame(width: Tokens.Spacing.sidebarWidth)
        .frame(maxHeight: .infinity)
        .background(theme.sidebar)
        .overlay(alignment: .trailing) { Rectangle().fill(theme.sidebarBorder).frame(width: 1) }
    }
}

private struct NavRow: View {
    @Environment(Theme.self) private var theme
    let route: Route
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 11) {
                if let icon = route.icon { IconView(icon: icon, size: 18, strokeWidth: 1.5) }
                Text(route.title).uiText(14, weight: isActive ? 500 : 400)
                Spacer(minLength: 0)
            }
            .foregroundStyle(isActive ? theme.ink : theme.ink2)
            .padding(.horizontal, 12)
            .frame(height: 36)
            .background(isActive ? theme.navActive : .clear, in: RoundedRectangle(cornerRadius: Tokens.Radius.nav))
            .contentShape(RoundedRectangle(cornerRadius: Tokens.Radius.nav))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }
}

private struct NextEditionCard: View {
    @Environment(Theme.self) private var theme
    let summary: NextEditionSummary?
    let action: () -> Void

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 12)
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                Kicker(text: "Next edition", size: 11)
                if let summary {
                    Text(summary.when)
                        .displayText(19, lineHeight: 1.2)
                        .foregroundStyle(theme.ink)
                    Text(summary.detail).uiText(13).foregroundStyle(theme.ink2)
                } else {
                    // Not designed: nothing scheduled yet.
                    Text("Nothing scheduled").displayText(19, lineHeight: 1.2).foregroundStyle(theme.ink)
                    Text("Set times in Schedule").uiText(13).foregroundStyle(theme.ink2)
                }
            }
            .lineLimit(1)
            // 14/14/16 padding plus the 1 pt border (the card is an `<a>`, CSS content-box).
            .padding(.top, 15)
            .padding(.horizontal, 15)
            .padding(.bottom, 17)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                theme.background
                    .overlay { WashStack(layers: [.right("wc-ochre", -70, top: -44, 190, 135, opacity: 0.7)]) }
            }
            .clipShape(shape)
            .overlay(shape.strokeBorder(theme.sidebarBorder, lineWidth: 1))
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
    }
}
