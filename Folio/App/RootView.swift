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
        // The system focus ring draws as slivers at the ends of the design's pill and card buttons.
        .focusEffectDisabled()
        .frame(minWidth: Tokens.Window.minWidth, minHeight: Tokens.Window.minHeight)
        .background(WindowChrome(trafficLightCenter: trafficLights, background: windowBackground,
                                  showsTrafficLights: !isReading || app.readerControlsVisible))
        .alert("Couldn’t add that file", isPresented: Binding(get: { app.library.importError != nil }, set: { if !$0 { app.library.importError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(app.library.importError ?? "")
        }
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            loadDroppedFiles(providers)
            return true
        }
    }

    private var isReading: Bool { app.route == .reader || app.route == .brief }

    private var windowBackground: NSColor {
        app.route.showsSidebar ? theme.palette.background.nsColor : theme.reading.background.nsColor
    }

    /// Sidebar.dc.html: 12 pt lights in a 14 pt row, 18 pt from the top, 8 pt in from the 12 pt padding.
    /// ReaderTools.dc.html: centred in the 72 pt header, 20 + 8 pt in.
    /// End / Onboarding: 18 pt from the top, 20 + 8 pt in.
    private var trafficLights: CGPoint {
        if app.route.showsSidebar { return CGPoint(x: 12 + 8 + 6, y: 18 + 7) }
        if isReading { return CGPoint(x: 20 + 8 + 6, y: 36) }
        return CGPoint(x: 20 + 8 + 6, y: 18 + 6)
    }

    /// EPUB and PDF files dropped anywhere on the window are imported.
    private func loadDroppedFiles(_ providers: [NSItemProvider]) {
        for provider in providers {
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url else { return }
                Task { @MainActor in app.importFiles([url]) }
            }
        }
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
