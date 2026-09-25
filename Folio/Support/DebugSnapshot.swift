#if DEBUG
import AppKit

/// DEBUG only: `-FolioSnapshot <name>` renders the main window (title-bar area and system buttons
/// included) to `<container>/tmp/folio-<name>.png` after launch, then quits. It's used by
/// tools/snap.sh for the visual check when `screencapture` has no Screen Recording permission.
@MainActor
enum DebugSnapshot {
    static func scheduleIfRequested() {
        guard let name = UserDefaults.standard.string(forKey: "FolioSnapshot") else { return }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            guard let window = NSApp.windows.first(where: { $0.isVisible && $0.frame.width >= 1000 }),
                  let frameView = window.contentView?.superview else { NSApp.terminate(nil); return }
            let bounds = frameView.bounds
            guard let rep = frameView.bitmapImageRepForCachingDisplay(in: bounds) else { NSApp.terminate(nil); return }
            frameView.cacheDisplay(in: bounds, to: rep)
            let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("folio-\(name).png")
            try? rep.representation(using: .png, properties: [:])?.write(to: url)
            print("Snapshot: \(url.path) window \(window.frame) content \(window.contentView?.frame ?? .zero) layout \(window.contentLayoutRect)")
            NSApp.terminate(nil)
        }
    }
}
#endif
