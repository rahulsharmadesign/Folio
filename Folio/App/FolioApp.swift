import SwiftUI

@main
struct FolioApp: App {
    static let mainWindowID = "main"

    @State private var theme: Theme
    @State private var app = AppState()

    init() {
        // Thin, even strokes like the approved renders (and the paper look): no font-smoothing
        // stem darkening. App domain only; a user's explicit global setting still wins.
        UserDefaults.standard.register(defaults: ["AppleFontSmoothing": 0])
        Fonts.register()
        _theme = State(initialValue: Theme())
        #if DEBUG
        DebugSnapshot.scheduleIfRequested()
        #endif
    }

    var body: some Scene {
        Window("Folio", id: Self.mainWindowID) {
            RootView()
                .environment(theme)
                .environment(app)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        .defaultSize(width: Tokens.Window.defaultWidth, height: Tokens.Window.defaultHeight)
        .windowBackgroundDragBehavior(.enabled)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }

        MenuBarExtra {
            MenuBarView()
                .environment(theme)
                .environment(app)
        } label: {
            Image(nsImage: MenuBarIcon.make())
                .accessibilityLabel("Folio")
        }
        .menuBarExtraStyle(.window)
    }
}
