import SwiftUI

/// Title (display 40) and one-line description (15, ink2) used by Library, Notebook, Schedule and Appearance.
struct ScreenHeader: View {
    @Environment(Theme.self) private var theme
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .textStyle(Tokens.screenTitle)
                .foregroundStyle(theme.ink)
                .accessibilityAddTraits(.isHeader)
            Text(subtitle).uiText(15).foregroundStyle(theme.ink2)
        }
    }
}

/// A sidebar screen with the source's content padding (64 top, 64 sides, 40 bottom) and only its header,
/// until its milestone builds the rest.
struct EmptySidebarScreen: View {
    let title: String
    let subtitle: String
    var padding = EdgeInsets(top: 64, leading: 64, bottom: 40, trailing: 64)

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScreenHeader(title: title, subtitle: subtitle)
            Spacer(minLength: 0)
        }
        .padding(padding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

/// A full-window screen (no sidebar) with a way back to Today, until its milestone builds it.
struct EmptyFullScreen: View {
    @Environment(Theme.self) private var theme
    @Environment(AppState.self) private var app
    let title: String

    var body: some View {
        ZStack(alignment: .topLeading) {
            PaperBackground()
            // Reader.dc.html header: 72 pt tall, 28 pt side padding, "‹ Today" in ink3.
            Button { app.route = .today } label: {
                HStack(spacing: 6) {
                    IconView(icon: .chevronLeft, size: 16, strokeWidth: 1.6)
                    Text("Today").uiText(13)
                }
                .foregroundStyle(theme.ink3)
                .padding(.horizontal, 8)
                .frame(height: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.leading, 28)
            .padding(.top, 14 + 28) // below the traffic lights
            .keyboardShortcut(.escape, modifiers: [])

            Text(title)
                .displayText(15, italic: true)
                .foregroundStyle(theme.ink3)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
