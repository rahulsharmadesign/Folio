import SwiftUI

/// Notebook & recall (08). Built in M5.
struct NotebookView: View {
    var body: some View {
        EmptySidebarScreen(title: "Notebook", subtitle: "Your highlights, notes and reflections, in one quiet place.",
                           padding: EdgeInsets(top: 64, leading: 64, bottom: 40, trailing: 56))
    }
}
