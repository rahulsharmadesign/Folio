import Foundation

/// Books read continuously (SPEC › Reader): the reader lays out a window of consecutive parts from one
/// chapter, and paging past either end moves to the next or previous window. Pure, so it's unit-tested.
enum BookWindows {
    /// At most this many parts per window (about 35,000 characters), so layout stays quick.
    static let maxParts = 16

    /// The window that starts at `start` and runs forward to the end of its chapter (or `maxParts`).
    /// `chapters` holds each part's chapter title, in part order.
    static func forward(from start: Int, chapters: [String]) -> ClosedRange<Int>? {
        guard chapters.indices.contains(start) else { return nil }
        var end = start
        while end + 1 < chapters.count, chapters[end + 1] == chapters[start], end + 1 - start < maxParts { end += 1 }
        return start...end
    }

    /// The window that ends at `end` and runs back to the start of its chapter (or `maxParts`).
    static func backward(to end: Int, chapters: [String]) -> ClosedRange<Int>? {
        guard chapters.indices.contains(end) else { return nil }
        var start = end
        while start > 0, chapters[start - 1] == chapters[end], end - (start - 1) < maxParts { start -= 1 }
        return start...end
    }

    /// The part a page belongs to: the last part whose text starts at or before the page's first character.
    /// `offsets` are each part's start in the laid-out text, in order.
    static func part(at location: Int, offsets: [(index: Int, offset: Int)]) -> Int? {
        offsets.last { $0.offset <= location }?.index ?? offsets.first?.index
    }
}
