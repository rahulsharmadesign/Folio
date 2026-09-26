import Foundation

enum Cadence: String, Codable, CaseIterable, Sendable {
    case once, twice, custom

    var title: String {
        switch self {
        case .once: "Once a day"
        case .twice: "Twice a day"
        case .custom: "Custom"
        }
    }
}

enum SlotContent: String, Codable, CaseIterable, Sendable {
    case passage, brief, passageAndBrief, publication

    var title: String {
        switch self {
        case .passage: "Passage"
        case .brief: "The Brief"
        case .passageAndBrief: "Passage + The Brief"
        case .publication: "Publication"
        }
    }
}

/// A delivery time (SPEC › ScheduleSlot).
struct ScheduleSlot: Codable, Hashable, Identifiable, Sendable {
    var id: String
    var hour: Int
    var minute: Int
    var content: SlotContent
    /// Calendar weekdays, 1 = Sunday … 7 = Saturday.
    var weekdays: Set<Int>

    static let everyDay: Set<Int> = Set(1...7)
    static let weekdaysOnly: Set<Int> = Set(2...6)
    static let weekends: Set<Int> = [1, 7]

    var time: String { String(format: "%02d:%02d", hour, minute) }
    var minutes: Int { hour * 60 + minute }

    var daysLabel: String {
        switch weekdays {
        case Self.everyDay: return "Every day"
        case Self.weekdaysOnly: return "Weekdays"
        case Self.weekends: return "Weekends"
        default:
            let symbols = Calendar.current.shortWeekdaySymbols
            return weekdays.sorted { ($0 + 5) % 7 < ($1 + 5) % 7 }.map { symbols[$0 - 1] }.joined(separator: ", ")
        }
    }

    /// Morning / afternoon / evening edition, from the time.
    var editionName: String {
        hour < 12 ? "Morning edition" : hour < 18 ? "Afternoon edition" : "Evening edition"
    }

    static func defaults(for cadence: Cadence) -> [ScheduleSlot] {
        switch cadence {
        case .once:
            [ScheduleSlot(id: "once-0700", hour: 7, minute: 0, content: .passageAndBrief, weekdays: everyDay)]
        case .twice:
            [ScheduleSlot(id: "twice-0700", hour: 7, minute: 0, content: .passage, weekdays: everyDay),
             ScheduleSlot(id: "twice-2100", hour: 21, minute: 0, content: .brief, weekdays: everyDay)]
        case .custom:
            [ScheduleSlot(id: "custom-0630", hour: 6, minute: 30, content: .passage, weekdays: weekdaysOnly),
             ScheduleSlot(id: "custom-1300", hour: 13, minute: 0, content: .publication, weekdays: [2, 4, 6]),
             ScheduleSlot(id: "custom-2130", hour: 21, minute: 30, content: .brief, weekdays: everyDay)]
        }
    }
}

/// One slot on one day.
struct SlotOccurrence: Hashable, Sendable {
    var slot: ScheduleSlot
    var date: Date
}

/// Pure schedule arithmetic, shared by the scheduler, Today, the sidebar and the menu bar.
enum SchedulePlanner {
    /// How far ahead an edition is prepared (SPEC: up to 1 hour).
    static let prepareAhead: TimeInterval = 3600

    static func occurrences(of slots: [ScheduleSlot], on day: Date, calendar: Calendar = .current) -> [SlotOccurrence] {
        let weekday = calendar.component(.weekday, from: day)
        let start = calendar.startOfDay(for: day)
        return slots.filter { $0.weekdays.contains(weekday) }
            .compactMap { slot in
                calendar.date(bySettingHour: slot.hour, minute: slot.minute, second: 0, of: start).map { SlotOccurrence(slot: slot, date: $0) }
            }
            .sorted { $0.date < $1.date }
    }

    /// The next occurrence strictly after `now` (looks a week ahead).
    static func next(after now: Date, slots: [ScheduleSlot], calendar: Calendar = .current) -> SlotOccurrence? {
        for offset in 0...7 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: now) else { continue }
            if let hit = occurrences(of: slots, on: day, calendar: calendar).first(where: { $0.date > now }) { return hit }
        }
        return nil
    }

    /// The latest occurrence at or before `now` today, if any.
    static func latestToday(before now: Date, slots: [ScheduleSlot], calendar: Calendar = .current) -> SlotOccurrence? {
        occurrences(of: slots, on: now, calendar: calendar).last { $0.date <= now }
    }

    /// Occurrences that should have an edition by `now`: everything today that has arrived or is within
    /// the preparation window.
    static func due(at now: Date, slots: [ScheduleSlot], calendar: Calendar = .current) -> [SlotOccurrence] {
        occurrences(of: slots, on: now, calendar: calendar).filter { $0.date.timeIntervalSince(now) <= prepareAhead }
    }

    /// "Tonight, 21:00", "Today, 13:00", "Tomorrow, 07:00", "Monday, 07:00".
    static func whenLabel(_ date: Date, now: Date, calendar: Calendar = .current) -> String {
        let time = timeLabel(date, calendar: calendar)
        if calendar.isDate(date, inSameDayAs: now) {
            return calendar.component(.hour, from: date) >= 18 ? "Tonight, \(time)" : "Today, \(time)"
        }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now), calendar.isDate(date, inSameDayAs: tomorrow) {
            return "Tomorrow, \(time)"
        }
        return date.formatted(.dateTime.weekday(.wide)) + ", " + time
    }

    static func timeLabel(_ date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
    }

    /// "in 10 h", "in 25 min"
    static func inLabel(_ date: Date, now: Date) -> String {
        let minutes = max(0, Int(date.timeIntervalSince(now) / 60))
        if minutes < 60 { return "in \(minutes) min" }
        return "in \(Int((Double(minutes) / 60).rounded())) h"
    }

    /// Never pile up: when a newer edition is ready, older unread ones are replaced.
    /// Returns the IDs to mark `replaced`, given (id, scheduledFor, state) of existing editions.
    static func toReplace(_ editions: [(id: UUID, date: Date, state: EditionState)], newestReady: Date) -> [UUID] {
        editions.filter { ($0.state == .ready || $0.state == .prepared) && $0.date < newestReady }.map(\.id)
    }
}

/// Reading time: 2,200 characters ≈ 4 minutes (Schedule.dc.html: len / 550).
enum ReadingTime {
    static let charactersPerMinute = 550.0

    static func minutes(_ characters: Int) -> Int { max(1, Int((Double(characters) / charactersPerMinute).rounded())) }

    /// "2 min left", "under a minute"
    static func leftLabel(_ characters: Int) -> String {
        let m = Double(characters) / charactersPerMinute
        return m < 1 ? "under a minute" : "\(Int(m.rounded())) min left"
    }

    /// "About four minutes."
    static func aboutWords(_ characters: Int) -> String {
        let words = ["", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten"]
        let m = minutes(characters)
        let w = m < words.count ? words[m] : "\(m)"
        return "About \(w) minute\(m == 1 ? "" : "s")."
    }

    /// Schedule's length label: "Up to 2,200 characters · about two pages · 4 min"
    static func lengthLabel(_ limit: Int) -> String {
        let pages = limit <= 1000 ? "half a page" : limit <= 1600 ? "about a page" : "about two pages"
        let mins = max(1, Int((Double(limit) / charactersPerMinute).rounded()))
        return "Up to \(limit.formatted(.number.locale(Locale(identifier: "en_US")))) characters · \(pages) · \(mins) min"
    }
}
