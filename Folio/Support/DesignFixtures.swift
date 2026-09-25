import SwiftUI

/// The mockups' sample content, shown only with `-FolioDesignFixtures YES` so screens can be
/// compared with design/screens/*.png. Real content replaces each piece in its milestone.
enum DesignFixtures {
    /// Saturday 26 September 2026, 08:00 — the morning in the mockups.
    static var now: Date {
        var c = DateComponents()
        c.year = 2026; c.month = 9; c.day = 26; c.hour = 8
        return Calendar.current.date(from: c) ?? .now
    }

    static let nextEdition = NextEditionSummary(when: "Tonight, 21:00", detail: "The Brief · honeybees")

    struct TodayEditions: View {
        var body: some View {
            HStack(alignment: .top, spacing: 24) {
                EditionCard(
                    washes: [.left("wc-lapis", -40, top: -70, 420, 300, opacity: 0.9),
                             .right("wc-sage", -60, top: 10, 360, 256, opacity: 0.75)],
                    badge: EditionBadge(text: "Morning edition · 07:00", kind: .ready),
                    kicker: "Passage · Walden, part 14 of 62",
                    title: "Where I Lived, and What I Lived For",
                    meta: "Henry David Thoreau · 4 min"
                ) {
                    Button {} label: { ButtonLabel(title: "Begin reading", trailingIcon: .arrowRight) }
                        .buttonStyle(.primary)
                    ContinuesLabel()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                EditionCard(
                    washes: [.left("wc-ochre", 30, top: -50, 400, 285, opacity: 0.8),
                             .right("wc-rose", -90, top: 40, 340, 242, opacity: 0.6)],
                    badge: EditionBadge(text: "Evening edition · 21:00", kind: .upcoming),
                    kicker: "The Brief · written for you",
                    title: "How honeybees choose a new home",
                    meta: "From your topic: collective behaviour · 4 min"
                ) {
                    Button("Arrives tonight · peek") {}
                        .buttonStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private struct ContinuesLabel: View {
        @Environment(Theme.self) private var theme
        var body: some View {
            Text("Continues from yesterday").uiText(13).foregroundStyle(theme.ink2)
        }
    }

    struct TodayResurfaced: View {
        var body: some View {
            QuoteCard(
                kicker: "Back from four days ago",
                quote: "“The mass of men lead lives of quiet desperation.”",
                source: "Walden · Economy"
            ) {
                Button("Keep") {}.buttonStyle(.secondaryCompact)
                Button("Let it go") {}.buttonStyle(.quiet)
            }
        }
    }
}
