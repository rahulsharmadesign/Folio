import Foundation

/// Content bundled so Folio has something to read on first launch.
enum SampleContent {
    /// Walden, from Project Gutenberg (#205, public domain in the USA). Bundled as Samples/walden.epub.
    static let waldenResource = "walden"
    static let waldenTitle = "Walden"

    static let briefTopic = "Collective behaviour"

    /// A sample Brief, written from the text of the four Wikipedia articles below (retrieved 26 Sep 2026),
    /// and nothing else — the same grounding rule the Brief pipeline enforces. 2,200 characters or less.
    static let brief = (
        title: "How honeybees choose a new home",
        standfirst: "Thousands of bees, no leader, and a decision that is usually right.",
        body: """
        Most often in spring, a crowded honeybee colony does something remarkable: it splits. The queen leaves with a portion of the workers, and the swarm hangs from a branch a few metres from the hive while it decides where to live next.

        The choice falls to a small group of scouts — the most experienced foragers in the cluster — who fly out to inspect hollow cavities. A good home holds roughly forty litres, has a small entrance near the bottom, gets some warmth from the sun and is free of ants.

        A scout that finds a promising site returns and performs a waggle dance on the swarm. The direction of her waggle runs points toward the site; how long they last encodes distance. The better the site, the more times she repeats the dance — and the more scouts go to see for themselves.

        Scouts that found poor cavities stop dancing sooner and can be recruited to better ones, so weaker options lose their advocates while stronger ones gather momentum. After several hours, sometimes days, a favourite emerges.

        No single bee compares every option. The swarm waits for a quorum: once enough scouts — usually somewhere between ten and thirty — are at the same site together, they return and begin *piping*, a vibration signal that sets the swarm moving. Soon the whole cloud lifts off and flies to its new home, sometimes a kilometre or more away.

        The Cornell biologist Thomas Seeley studies how bees make decisions together; his books include *Honeybee Democracy*. In one experiment, swarms deciding this way chose the best available site in four out of five trials — with no one in charge.
        """,
        sources: [
            BriefSource(title: "Swarming (honey bee)", url: "https://en.wikipedia.org/wiki/Swarming_(honey_bee)", publisher: "Wikipedia", year: "2026"),
            BriefSource(title: "Waggle dance", url: "https://en.wikipedia.org/wiki/Waggle_dance", publisher: "Wikipedia", year: "2026"),
            BriefSource(title: "Quorum sensing", url: "https://en.wikipedia.org/wiki/Quorum_sensing", publisher: "Wikipedia", year: "2026"),
            BriefSource(title: "Thomas Dyer Seeley", url: "https://en.wikipedia.org/wiki/Thomas_Dyer_Seeley", publisher: "Wikipedia", year: "2026"),
        ]
    )
}
