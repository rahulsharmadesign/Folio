import Foundation

/// Spaced repetition for highlights: 4 days → 2 weeks → 1 month → 3 months (SPEC › Notebook).
enum Recall {
    /// Days until each review; stage 0 is the first.
    static let intervals = [4, 14, 30, 90]

    static func firstReview(after date: Date, calendar: Calendar = .current) -> Date? {
        calendar.date(byAdding: .day, value: intervals[0], to: date)
    }

    /// After "Keep": the next review, or nil once the last interval has passed (it's learnt).
    static func keep(stage: Int, now: Date, calendar: Calendar = .current) -> (stage: Int, next: Date?) {
        let next = stage + 1
        guard next < intervals.count else { return (next, nil) }
        return (next, calendar.date(byAdding: .day, value: intervals[next], to: now))
    }

    static func isDue(_ next: Date?, now: Date) -> Bool {
        guard let next else { return false }
        return next <= now
    }

    /// "two weeks, then a month" for the Resurfacing card.
    static func upcomingPhrase(afterStage stage: Int) -> String {
        let names = ["four days", "two weeks", "a month", "three months"]
        let rest = Array(names.dropFirst(stage + 1).prefix(2))
        switch rest.count {
        case 0: return ""
        case 1: return "Keep it and it returns in \(rest[0]) — spaced so it sticks."
        default: return "Keep it and it returns in \(rest[0]), then \(rest[1]) — spaced so it sticks."
        }
    }

    /// "4 days ago", "today", "yesterday".
    static func ago(_ date: Date, now: Date = .now, calendar: Calendar = .current) -> String {
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: calendar.startOfDay(for: now)).day ?? 0
        switch days {
        case ..<1: return "today"
        case 1: return "yesterday"
        default:
            let words = ["", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten"]
            return days < words.count ? "\(words[days]) days ago" : "\(days) days ago"
        }
    }
}
