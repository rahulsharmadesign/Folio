import SwiftUI

/// Menu bar extra (11, MenuBar.dc.html), 360×460. M2 adds the ready and next edition cards
/// and pausing; this stub has the header and the actions.
struct MenuBarView: View {
    @Environment(Theme.self) private var theme
    @Environment(AppState.self) private var app
    @Environment(\.openWindow) private var openWindow
    /// The menu bar extra's own panel; `.window`-style extras don't close themselves after an action.
    @State private var panel = PanelReference()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Folio").displayText(20, italic: true).foregroundStyle(theme.ink)
                Spacer()
                Text(Date.now.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)))
                    .uiText(12).foregroundStyle(theme.ink2)
            }
            .padding(.vertical, 2)
            .padding(.horizontal, 4)

            Spacer(minLength: 0)

            VStack(alignment: .leading, spacing: 0) {
                row("Pause editions for today") {}
                    .disabled(true) // M2
                row("Open Folio") { open(.today) }
                row("Settings…", shortcut: "⌘ ,") { open(.schedule) }
            }
            .padding(.top, 6)
            .overlay(alignment: .top) { Rectangle().fill(theme.rule).frame(height: 1) }
        }
        .padding(16)
        .frame(width: 360, height: 460)
        .background(theme.background)
        .background(PanelReader(reference: panel))
    }

    private func open(_ route: Route) {
        panel.window?.close()
        app.route = route
        openWindow(id: FolioApp.mainWindowID)
        NSApp.activate()
    }

    private func row(_ title: String, shortcut: String? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(title).uiText(14).foregroundStyle(theme.ink)
                Spacer()
                if let shortcut { Text(shortcut).uiText(12).foregroundStyle(theme.ink2) }
            }
            .padding(.horizontal, 8)
            .frame(height: 36)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

@MainActor
private final class PanelReference {
    weak var window: NSWindow?
}

/// Captures the window hosting the menu bar extra's content.
private struct PanelReader: NSViewRepresentable {
    let reference: PanelReference

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        Task { @MainActor in reference.window = view.window }
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        if let window = view.window { reference.window = window }
    }
}

/// The book icon from the sidebar, as a template image for the status item.
@MainActor
enum MenuBarIcon {
    static func make() -> NSImage {
        let renderer = ImageRenderer(content: IconView(icon: .library, size: 18, strokeWidth: 1.5))
        renderer.scale = 2
        let image = renderer.nsImage ?? NSImage()
        image.size = NSSize(width: 18, height: 18)
        image.isTemplate = true
        return image
    }
}
