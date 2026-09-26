import SwiftData
import SwiftUI

/// The Brief (06, 06b): the paged reader with a Brief. Opened without one (the sidebar's
/// "Next edition" card), it shows the next unread Brief, or the latest.
struct BriefView: View {
    @Environment(AppState.self) private var app
    @Query(sort: \Brief.createdAt, order: .reverse) private var briefs: [Brief]

    var body: some View {
        Group {
            if app.reading?.isBrief == true {
                ReaderView()
            } else if briefs.isEmpty {
                EmptyFullScreen(title: "No Brief yet. Turn on AI in Settings, and add a topic in Library.")
            } else {
                Color.clear
            }
        }
        .onAppear(perform: pick)
        .onChange(of: briefs.count) { pick() }
    }

    private func pick() {
        guard app.reading?.isBrief != true else { return }
        if let brief = briefs.last(where: { $0.readAt == nil }) ?? briefs.first {
            app.reading = .brief(brief, nil)
        }
    }
}
