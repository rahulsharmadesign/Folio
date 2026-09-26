import AppKit
import SwiftUI

/// Window tweaks SwiftUI can't express: paper behind the hidden title bar, and the system
/// traffic lights moved to where the design places them. They're the real buttons; never draw them.
struct WindowChrome: NSViewRepresentable {
    /// Centre of the close button, from the window's top-left corner.
    var trafficLightCenter: CGPoint
    var background: NSColor
    /// Hidden while reading in focus mode (03): only the page is on screen.
    var showsTrafficLights = true

    func makeNSView(context: Context) -> NSView {
        let view = ChromeView()
        view.trafficLightCenter = trafficLightCenter
        view.background = background
        view.showsTrafficLights = showsTrafficLights
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        guard let view = view as? ChromeView else { return }
        view.trafficLightCenter = trafficLightCenter
        view.background = background
        view.showsTrafficLights = showsTrafficLights
        view.apply()
    }

    final class ChromeView: NSView {
        var trafficLightCenter = CGPoint(x: 26, y: 25)
        var background: NSColor = .windowBackgroundColor
        var showsTrafficLights = true
        private var observers: [NSObjectProtocol] = []

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            observers.forEach(NotificationCenter.default.removeObserver)
            observers.removeAll()
            guard let window else { return }
            let names: [Notification.Name] = [NSWindow.didResizeNotification, NSWindow.didEndLiveResizeNotification,
                                              NSWindow.didExitFullScreenNotification, NSWindow.didBecomeKeyNotification]
            for name in names {
                observers.append(NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.apply() }
                })
            }
            apply()
        }

        func apply() {
            place()
            // AppKit lays the title bar out again after it grows; place the buttons once more after that.
            DispatchQueue.main.async { [weak self] in self?.place() }
        }

        private func place() {
            guard let window else { return }
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.backgroundColor = background
            window.isMovableByWindowBackground = false
            guard !window.styleMask.contains(.fullScreen),
                  let close = window.standardWindowButton(.closeButton),
                  let titlebar = close.superview?.superview else { return }

            // Make the title bar tall enough to hold the buttons at their designed height.
            let size = close.frame.size
            let needed = trafficLightCenter.y + size.height / 2 + 6
            if let frameView = window.contentView?.superview {
                var frame = titlebar.frame
                frame.size.height = needed
                frame.origin.y = frameView.bounds.height - needed
                titlebar.frame = frame
            }
            let buttons: [NSWindow.ButtonType] = [.closeButton, .miniaturizeButton, .zoomButton]
            for (i, type) in buttons.enumerated() {
                guard let button = window.standardWindowButton(type), let parent = button.superview else { continue }
                button.animator().alphaValue = showsTrafficLights ? 1 : 0
                button.isEnabled = showsTrafficLights
                // 20 pt between centres, as in the mockups (12 pt lights, 8 pt gaps).
                let centerX = trafficLightCenter.x + CGFloat(i) * 20
                let yFromTop = trafficLightCenter.y
                let parentTopInWindow = parent.convert(CGPoint(x: 0, y: parent.isFlipped ? 0 : parent.bounds.height), to: nil).y
                let windowHeight = window.frame.height
                let parentTopFromWindowTop = windowHeight - parentTopInWindow
                let yInParentFromTop = yFromTop - parentTopFromWindowTop
                let originY = parent.isFlipped ? yInParentFromTop - size.height / 2
                                               : parent.bounds.height - yInParentFromTop - size.height / 2
                button.setFrameOrigin(CGPoint(x: centerX - size.width / 2, y: originY))
            }
        }
    }
}
