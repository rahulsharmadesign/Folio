import SwiftUI

/// The main window: the custom sidebar beside sidebar routes, full-window screens otherwise.
struct RootView: View {
    @Environment(Theme.self) private var theme
    @Environment(AppState.self) private var app

    var body: some View {
        @Bindable var app = app
        ZStack {
            theme.background.ignoresSafeArea()
            if app.route.showsSidebar {
                HStack(spacing: 0) {
                    FolioSidebar(selection: $app.route, nextEdition: app.nextEdition) {
                        app.route = .brief
                    }
                    // Like the CSS source: content that outgrows the window spills off the
                    // bottom rather than re-centring (which would also stretch the sidebar).
                    GeometryReader { geo in
                        screen(for: app.route)
                            .frame(width: geo.size.width, height: geo.size.height, alignment: .top)
                    }
                    .clipped()
                }
            } else {
                screen(for: app.route)
            }
        }
        .ignoresSafeArea()
        .frame(minWidth: Tokens.Window.minWidth, minHeight: Tokens.Window.minHeight)
        .background(WindowChrome(trafficLightCenter: trafficLights, background: theme.palette.background.nsColor))
    }

    /// Sidebar.dc.html: 12 pt lights in a 14 pt row, 18 pt from the top, 8 pt in from the 12 pt padding.
    /// Reader.dc.html: in the 72 pt header, 20 + 8 pt in.
    private var trafficLights: CGPoint {
        app.route.showsSidebar ? CGPoint(x: 12 + 8 + 6, y: 18 + 7) : CGPoint(x: 20 + 8 + 6, y: 36)
    }

    @ViewBuilder
    private func screen(for route: Route) -> some View {
        switch route {
        case .today: TodayView()
        case .library: LibraryView()
        case .notebook: NotebookView()
        case .schedule: ScheduleView()
        case .appearance: AppearanceView()
        case .reader: ReaderView()
        case .brief: BriefView()
        case .editionEnd: EditionEndView()
        case .onboarding: OnboardingView()
        }
    }
}
