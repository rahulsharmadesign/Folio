import SwiftUI

/// Appearance (10). Built in M5; it edits the global `Theme`.
struct AppearanceView: View {
    var body: some View {
        EmptySidebarScreen(title: "Appearance", subtitle: "Make the page yours. Changes preview on the right.",
                           padding: EdgeInsets(top: 56, leading: 64, bottom: 32, trailing: 56))
    }
}
