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
        let weekdays = [ScheduleSlot(id: "w", hour: 7, minute: 0, content: .passage, weekdays: ScheduleSlot.weekdaysOnly)]
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
        let draft = try await BriefPipeline.run(topic: "anything", pastAngles: [], deeper: nil, provider: StubProvider(reply: #"{"angle": "a", "query": "q"}"#),
                                                retrieve: { _ in [] })
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
