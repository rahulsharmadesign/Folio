import Foundation
import Testing
@testable import Folio

struct SchedulePlannerTests {
    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/London")!
        return c
    }

    /// Saturday 26 September 2026 at the given time.
    private func sat(_ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 9, day: 26, hour: hour, minute: minute))!
    }

    private let twice = ScheduleSlot.defaults(for: .twice)

    @Test func nextSlotToday() {
        let next = SchedulePlanner.next(after: sat(8), slots: twice, calendar: calendar)
        #expect(next?.slot.hour == 21)
        #expect(next.map { calendar.isDate($0.date, inSameDayAs: sat(8)) } == true)
    }

    @Test func nextSlotRollsToTomorrow() {
        let next = SchedulePlanner.next(after: sat(22), slots: twice, calendar: calendar)
        #expect(next?.slot.hour == 7)
        #expect(SchedulePlanner.whenLabel(next!.date, now: sat(22), calendar: calendar) == "Tomorrow, 07:00")
    }

    @Test func weekdayOnlySlotsSkipTheWeekend() {
        let weekdays = [ScheduleSlot(id: "w", hour: 7, minute: 0, content: .story, weekdays: ScheduleSlot.weekdaysOnly)]
        #expect(SchedulePlanner.occurrences(of: weekdays, on: sat(12), calendar: calendar).isEmpty)
        let next = SchedulePlanner.next(after: sat(12), slots: weekdays, calendar: calendar)!
        #expect(calendar.component(.weekday, from: next.date) == 2) // Monday
    }

    @Test func editionsArePreparedUpToAnHourAhead() {
        #expect(SchedulePlanner.due(at: sat(5, 30), slots: twice, calendar: calendar).isEmpty)
        #expect(SchedulePlanner.due(at: sat(6, 15), slots: twice, calendar: calendar).map(\.slot.hour) == [7])
        #expect(SchedulePlanner.due(at: sat(20, 30), slots: twice, calendar: calendar).map(\.slot.hour) == [7, 21])
    }

    @Test func whenLabels() {
        #expect(SchedulePlanner.whenLabel(sat(21), now: sat(8), calendar: calendar) == "Tonight, 21:00")
        #expect(SchedulePlanner.whenLabel(sat(13), now: sat(8), calendar: calendar) == "Today, 13:00")
        #expect(SchedulePlanner.inLabel(sat(21), now: sat(11)) == "in 10 h")
    }

    @Test func neverPileUpReplacesOnlyOlderUnreadEditions() {
        let a = UUID(), b = UUID(), c = UUID(), d = UUID()
        let editions: [(id: UUID, date: Date, state: EditionState)] = [
            (a, sat(7), .ready),      // unread, older → replaced
            (b, sat(7), .read),       // read → kept
            (c, sat(21), .ready),     // the new one → kept
            (d, sat(6), .prepared),   // never became ready, older → replaced
        ]
        #expect(Set(SchedulePlanner.toReplace(editions, newestReady: sat(21))) == [a, d])
    }
}

struct ReadingTimeTests {
    @Test func twentyTwoHundredCharactersIsAboutFourMinutes() {
        #expect(ReadingTime.minutes(2200) == 4)
        #expect(ReadingTime.aboutWords(2200) == "About four minutes.")
        #expect(ReadingTime.leftLabel(300) == "under a minute")
        #expect(ReadingTime.lengthLabel(2200) == "Up to 2,200 characters · about two pages · 4 min")
        #expect(ReadingTime.lengthLabel(800) == "Up to 800 characters · half a page · 1 min")
    }
}

struct RecallTests {
    private let start = Date(timeIntervalSince1970: 1_790_000_000)
    private let calendar = Calendar(identifier: .gregorian)

    private func days(_ from: Date, _ to: Date?) -> Int? {
        to.map { calendar.dateComponents([.day], from: from, to: $0).day! }
    }

    @Test func intervalsAreFourDaysTwoWeeksAMonthThreeMonths() {
        #expect(days(start, Recall.firstReview(after: start, calendar: calendar)) == 4)
        var stage = 0
        var gaps: [Int?] = []
        for _ in 0..<4 {
            let next = Recall.keep(stage: stage, now: start, calendar: calendar)
            stage = next.stage
            gaps.append(days(start, next.next))
        }
        #expect(gaps == [14, 30, 90, nil])
    }

    @Test func dueOnlyWhenTheDateHasPassed() {
        #expect(Recall.isDue(start, now: start.addingTimeInterval(1)))
        #expect(!Recall.isDue(start.addingTimeInterval(60), now: start))
        #expect(!Recall.isDue(nil, now: start))
    }

    @Test func agoLabels() {
        let four = calendar.date(byAdding: .day, value: -4, to: start)!
        #expect(Recall.ago(four, now: start, calendar: calendar) == "four days ago")
        #expect(Recall.ago(start, now: start, calendar: calendar) == "today")
    }
}

struct BriefValidationTests {
    private let sources = [
        RetrievedSource(title: "Swarming (honey bee)", url: "https://en.wikipedia.org/wiki/Swarming_(honey_bee)", text: "…"),
        RetrievedSource(title: "Waggle dance", url: "https://en.wikipedia.org/wiki/Waggle_dance", text: "…"),
    ]

    @Test func acceptsAGroundedBriefWithinTheLimit() throws {
        let reply = #"Here you go: {"title": "Bees", "standfirst": "A swarm decides.", "body": "Scouts dance.", "sources": [2]}"#
        let draft = try BriefPipeline.validate(reply, sources: sources, limit: 2200).get()
        #expect(draft.sources.map(\.title) == ["Waggle dance"])
    }

    @Test func rejectsASourceItWasNotGiven() {
        let reply = #"{"title": "Bees", "standfirst": "", "body": "Scouts dance.", "sources": [1, 3]}"#
        #expect(throws: BriefPipeline.Problem.self) { try BriefPipeline.validate(reply, sources: sources, limit: 2200).get() }
    }

    @Test func rejectsTooLong() {
        let body = String(repeating: "word ", count: 500)
        let reply = #"{"title": "Bees", "standfirst": "", "body": "\#(body)", "sources": [1]}"#
        #expect(throws: BriefPipeline.Problem.self) { try BriefPipeline.validate(reply, sources: sources, limit: 2200).get() }
    }

    @Test func rejectsNoSources() {
        let reply = #"{"title": "Bees", "standfirst": "", "body": "Scouts dance.", "sources": []}"#
        #expect(throws: BriefPipeline.Problem.self) { try BriefPipeline.validate(reply, sources: sources, limit: 2200).get() }
    }

    @Test func noRetrievedSourcesMeansNoBrief() async throws {
        let draft = try await BriefPipeline.run(BriefRequest(kind: .topic, topic: "anything"), provider: StubProvider(reply: #"{"angle": "a", "query": "q"}"#),
                                                retrieval: .offline())
        #expect(draft == nil)
    }

    @Test func newsBriefCitesTheFeedItemsItWasGiven() async throws {
        let items = [RetrievedSource(title: "A chip ships", url: "https://news.example/chip", text: "A new chip shipped.", publisher: "Example News", year: "2026")]
        let reply = #"{"title": "Chips", "standfirst": "One story.", "body": "A new chip shipped, Example News reports.", "sources": [1]}"#
        let draft = try #require(try await BriefPipeline.run(BriefRequest(kind: .news, feeds: ["https://news.example/feed"]),
                                                             provider: StubProvider(reply: reply), retrieval: .offline(news: items)))
        #expect(draft.sources == [BriefSource(title: "A chip ships", url: "https://news.example/chip", publisher: "Example News", year: "2026")])
    }

    @Test func aPickedQuoteMustAppearInItsSource() {
        let quotes = [RetrievedSource(title: "Steve Jobs", url: "https://en.wikiquote.org/wiki/Steve_Jobs",
                                      text: "Stay hungry. Stay foolish. — Stanford commencement address", publisher: "Wikiquote")]
        let good = #"{"quote": "Stay Hungry, stay foolish.", "title": "Hunger", "standfirst": "“Stay hungry.”", "body": "It closed a speech.", "sources": [1]}"#
        let made = #"{"quote": "Never stop dreaming big dreams", "title": "Dreams", "standfirst": "", "body": "…", "sources": [1]}"#
        #expect((try? BriefPipeline.validate(good, sources: quotes, limit: 2200, quoteMustAppear: true).get())?.subject == "Stay Hungry, stay foolish.")
        #expect(throws: BriefPipeline.Problem.self) { try BriefPipeline.validate(made, sources: quotes, limit: 2200, quoteMustAppear: true).get() }
    }

    @Test func aReadersQuoteWithNoSourceGivesNoBrief() async throws {
        let draft = try await BriefPipeline.run(BriefRequest(kind: .quote, quote: "Words nobody wrote down"), provider: StubProvider(reply: "{}"),
                                                retrieval: .offline())
        #expect(draft == nil)
    }

    @Test func sampleBriefIsWithinTheLimit() {
        let s = SampleContent.brief
        #expect(s.title.count + s.standfirst.count + s.body.count <= 2200)
        #expect(!s.sources.isEmpty)
    }

    @Test func recapIsClampedTo140() {
        let long = String(repeating: "Thoreau walked on. ", count: 20)
        #expect(Prompts.clampRecap(long).count <= 140)
    }
}

private struct StubProvider: AIProvider {
    let id = "stub"
    var reply: String
    var isAvailable: Bool { get async { true } }
    func stream(_ req: AIRequest) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { $0.yield(reply); $0.finish() }
    }
}

extension BriefRetrieval {
    static func offline(news: [RetrievedSource] = []) -> BriefRetrieval {
        BriefRetrieval(wikipedia: { _ in [] }, wikiquote: { _ in [] }, news: { _, _ in news })
    }
}

struct SlotContentTests {
    @Test func olderSchedulesDecodeAsBriefKinds() throws {
        let json = Data(#"["passage", "brief", "passageAndBrief", "publication", "news"]"#.utf8)
        #expect(try JSONDecoder().decode([SlotContent].self, from: json) == [.mix, .topic, .mix, .mix, .news])
    }

    @Test func aMixRotatesThroughEveryKind() {
        let calendar = Calendar(identifier: .gregorian)
        let start = calendar.date(from: DateComponents(year: 2026, month: 9, day: 28, hour: 7))!
        let kinds = (0..<4).map { SlotContent.mix.briefKind(on: calendar.date(byAdding: .day, value: $0, to: start)!, hour: 7, calendar: calendar) }
        #expect(Set(kinds) == Set(BriefKind.allCases))
        #expect(SlotContent.mix.briefKind(on: start, hour: 7, calendar: calendar) != SlotContent.mix.briefKind(on: start, hour: 21, calendar: calendar))
        #expect(SlotContent.news.briefKind(on: start, hour: 7) == .news)
    }
}

struct BookWindowTests {
    // Parts 0–2 in "One", 3–4 in "Two", then 40 untitled parts (a PDF).
    private let chapters = ["One", "One", "One", "Two", "Two"] + Array(repeating: "", count: 40)

    @Test func forwardRunsToTheEndOfTheChapter() {
        #expect(BookWindows.forward(from: 0, chapters: chapters) == 0...2)
        #expect(BookWindows.forward(from: 1, chapters: chapters) == 1...2) // resuming mid-chapter
        #expect(BookWindows.forward(from: 3, chapters: chapters) == 3...4)
    }

    @Test func backwardRunsToTheStartOfTheChapter() {
        #expect(BookWindows.backward(to: 2, chapters: chapters) == 0...2)
        #expect(BookWindows.backward(to: 4, chapters: chapters) == 3...4)
    }

    @Test func longChaptersAreCapped() {
        #expect(BookWindows.forward(from: 5, chapters: chapters) == 5...(5 + BookWindows.maxParts - 1))
        #expect(BookWindows.backward(to: 44, chapters: chapters) == (44 - BookWindows.maxParts + 1)...44)
        #expect(BookWindows.forward(from: 45, chapters: chapters) == nil)
    }

    @Test func aPageBelongsToThePartItStartsIn() {
        let offsets = [(index: 3, offset: 0), (index: 4, offset: 2000), (index: 5, offset: 4100)]
        #expect(BookWindows.part(at: 0, offsets: offsets) == 3)
        #expect(BookWindows.part(at: 2500, offsets: offsets) == 4)
        #expect(BookWindows.part(at: 9000, offsets: offsets) == 5)
    }
}

struct FeedTests {
    private let rss = Data("""
    <?xml version="1.0"?><rss version="2.0" xmlns:content="http://purl.org/rss/1.0/modules/content/"><channel><title>Example News</title>
    <item><title>Old story</title><link>https://news.example/old</link><pubDate>Mon, 01 Jan 2024 10:00:00 +0000</pubDate></item>
    <item><title>A chip &amp; a board</title><link>https://news.example/chip</link><description>&lt;p&gt;Short.&lt;/p&gt;</description>
    <content:encoded><![CDATA[<p>A new <b>chip</b> shipped today.</p>]]></content:encoded><pubDate>Sun, 27 Sep 2026 09:30:00 +0000</pubDate></item>
    </channel></rss>
    """.utf8)

    private let atom = Data("""
    <?xml version="1.0" encoding="utf-8"?><feed xmlns="http://www.w3.org/2005/Atom"><title type="text">Atom Daily</title>
    <entry><title>Robots</title><link rel="alternate" href="https://atom.example/robots"/><updated>2026-09-27T12:00:00Z</updated>
    <summary type="html">&lt;p&gt;Robots learned to fold laundry.&lt;/p&gt;</summary></entry></feed>
    """.utf8)

    @Test func parsesRSSWithTheFullestBody() throws {
        let feed = try #require(FeedParser.parse(rss))
        #expect(feed.title == "Example News")
        #expect(feed.items.count == 2)
        #expect(feed.items[1].title == "A chip & a board")
        #expect(feed.items[1].summary == "A new chip shipped today.")
        #expect(feed.items[1].date != nil)
    }

    @Test func parsesAtom() throws {
        let feed = try #require(FeedParser.parse(atom))
        #expect(feed.title == "Atom Daily")
        #expect(feed.items.first?.link == "https://atom.example/robots")
        #expect(feed.items.first?.summary == "Robots learned to fold laundry.")
    }

    @Test func selectsRecentUnseenItemsNewestFirst() throws {
        let now = FeedDates.parse("2026-09-28T08:00:00Z")!
        let feeds = [(url: "https://news.example/feed", feed: try #require(FeedParser.parse(rss))),
                     (url: "https://atom.example/feed", feed: try #require(FeedParser.parse(atom)))]
        let picked = FeedRetrieval.select(feeds, excluding: [], now: now, limit: 10)
        #expect(picked.map(\.url) == ["https://atom.example/robots", "https://news.example/chip"]) // the 2024 story is too old
        #expect(picked.last?.publisher == "Example News")
        let unseen = FeedRetrieval.select(feeds, excluding: ["https://atom.example/robots"], now: now, limit: 10)
        #expect(unseen.map(\.url) == ["https://news.example/chip"])
    }
}

struct BriefParagraphTests {
    @Test func aSingleBlockIsSplitIntoShortParagraphs() {
        let body = (1...10).map { "Sentence number \($0) is here." }.joined(separator: " ")
        let split = BriefParagraphs.ensure(body)
        let paragraphs = split.components(separatedBy: "\n\n")
        #expect((3...5).contains(paragraphs.count))
        #expect(paragraphs.joined(separator: " ") == body)
        #expect(BriefParagraphs.ensure(split) == split)
    }

    @Test func singleLineBreaksBecomeParagraphs() {
        #expect(BriefParagraphs.ensure("One.\nTwo.") == "One.\n\nTwo.")
    }
}
