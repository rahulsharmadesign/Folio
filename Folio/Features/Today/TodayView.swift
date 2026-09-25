import SwiftUI

/// Today (02, Main.dc.html). M1 fills the edition cards from the library; until then it shows the
/// frame: date, greeting, a status line and the closing line.
struct TodayView: View {
    @Environment(Theme.self) private var theme
    @Environment(AppState.self) private var app

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            header

            if app.designFixtures {
                DesignFixtures.TodayEditions()
                DesignFixtures.TodayResurfaced()
            }

            // `margin-top: auto`: pinned to the bottom, or straight after the content when it overflows.
            Text("Nothing else today. That’s the point.")
                .displayText(16, italic: true)
                .foregroundStyle(theme.ink2)
                .frame(maxHeight: .infinity, alignment: .bottomLeading)
        }
        .padding(.top, 56)
        .padding(.horizontal, 72)
        .padding(.bottom, 40)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(Greeting.dateLine(for: now))
                .uiText(13, tracking: 0.01)
                .foregroundStyle(theme.ink2)
            Text(Greeting.greeting(for: now, name: name))
                .textStyle(Tokens.greeting)
                .foregroundStyle(theme.ink)
                .accessibilityAddTraits(.isHeader)
            Text(status)
                .uiText(16)
                .foregroundStyle(theme.ink2)
        }
    }

    private var now: Date { app.designFixtures ? DesignFixtures.now : .now }
    private var name: String? { app.designFixtures ? "Rahul" : Greeting.firstName }

    private var status: String {
        // The empty-library line isn't designed; flagged for review.
        app.designFixtures ? "Your morning edition is ready. About four minutes."
            : "No editions yet. Add a book in Library and your first one will be here."
    }
}

enum Greeting {
    static func greeting(for date: Date, name: String?, calendar: Calendar = .current) -> String {
        let hour = calendar.component(.hour, from: date)
        let part = hour < 12 ? "morning" : hour < 18 ? "afternoon" : "evening"
        if let name, !name.isEmpty { return "Good \(part), \(name)." }
        return "Good \(part)."
    }

    /// "Saturday, 26 September"
    static func dateLine(for date: Date, locale: Locale = .current) -> String {
        date.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(locale))
    }

    static var firstName: String? {
        NSFullUserName().split(separator: " ").first.map(String.init)
    }
}
