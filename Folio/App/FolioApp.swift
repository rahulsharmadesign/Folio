import SwiftData
import SwiftUI

@main
struct FolioApp: App {
    static let mainWindowID = "main"

    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var app: AppState

    init() {
        // Thin, even strokes like the approved renders (and the paper look): no font-smoothing
        // stem darkening. App domain only; a user's explicit global setting still wins.
        UserDefaults.standard.register(defaults: ["AppleFontSmoothing": 0])
        Fonts.register()
        _app = State(initialValue: AppState())
        #if DEBUG
        DebugSnapshot.scheduleIfRequested()
        #endif
    }

    var body: some Scene {
        Window("Folio", id: Self.mainWindowID) {
            RootView()
                .environment(app.theme)
                .environment(app)
                .modelContainer(app.container)
                .task { await app.start() }
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        .defaultSize(width: Tokens.Window.defaultWidth, height: Tokens.Window.defaultHeight)
        .windowBackgroundDragBehavior(.enabled)
        .commands { FolioCommands(app: app) }

        Settings {
            SettingsView()
                .environment(app.theme)
                .environment(app)
                .modelContainer(app.container)
        }

        MenuBarExtra {
            MenuBarView()
                .environment(app.theme)
                .environment(app)
                .modelContainer(app.container)
        } label: {
            Image(nsImage: MenuBarIcon.make(dot: app.scheduler.readyUnread(now: app.now) != nil && app.scheduler.version >= 0))
                .accessibilityLabel("Folio")
        }
        .menuBarExtraStyle(.window)
    }
}

/// File › Open (⌘O) and the reader's keyboard shortcuts in the menus.
struct FolioCommands: Commands {
    let app: AppState

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("Open…") { OpenPanel.chooseBooks { app.importFiles($0) } }
                .keyboardShortcut("o")
        }
        CommandMenu("Go") {
            Button("Today") { app.route = .today }.keyboardShortcut("1")
            Button("Library") { app.route = .library }.keyboardShortcut("2")
            Button("Notebook") { app.route = .notebook }.keyboardShortcut("3")
            Button("Schedule") { app.route = .schedule }.keyboardShortcut("4")
            Button("Appearance") { app.route = .appearance }.keyboardShortcut("5")
        }
    }
}

/// Open With › Folio and drops on the Dock icon.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func application(_ application: NSApplication, open urls: [URL]) {
        MainActor.assumeIsolated {
            AppState.shared?.importFiles(urls)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}

/// The EPUB/PDF file picker.
@MainActor
enum OpenPanel {
    static func chooseBooks(_ completion: @escaping ([URL]) -> Void) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = LibraryStore.supportedTypes
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.prompt = "Add"
        panel.message = "Choose EPUB or PDF files to add to your library."
        panel.begin { response in
            if response == .OK { completion(panel.urls) }
        }
    }
}
