import Foundation
import NaturalLanguage

/// A chapter of a source text, as importers produce it.
struct SourceChapter: Sendable, Equatable, Codable {
    var title: String
    var paragraphs: [String]
}

/// One edition-sized part.
struct ChunkedPart: Sendable, Equatable {
    var index: Int
    var chapterTitle: String
    /// Paragraphs joined by a blank line.
    var text: String
}

/// Splits chapters into parts of `limit` characters or less (SPEC › Chunker).
///
/// Parts are built greedily from whole paragraphs. A paragraph longer than the limit is split at sentence
/// boundaries (`NLTokenizer(.sentence)`). A part never crosses a chapter boundary; a chapter's last part may
/// be short. Deterministic: the same input always gives the same parts.
enum Chunker {
    static let defaultLimit = 2200
    static let limitRange = 800...2200
    static let paragraphSeparator = "\n\n"

    static func chunk(_ chapters: [SourceChapter], limit requested: Int = defaultLimit) -> [ChunkedPart] {
        let limit = min(max(requested, limitRange.lowerBound), limitRange.upperBound)
        var parts: [ChunkedPart] = []
        for chapter in chapters {
            let paragraphs = chapter.paragraphs.map(clean).filter { !$0.isEmpty }
            guard !paragraphs.isEmpty else { continue }
            for text in chunkChapter(paragraphs, limit: limit) {
                parts.append(ChunkedPart(index: parts.count, chapterTitle: chapter.title, text: text))
            }
        }
        return parts
    }

    private static func chunkChapter(_ paragraphs: [String], limit: Int) -> [String] {
        var parts: [String] = []
        var current: [String] = []
        var currentLength = 0

        func flush() {
            if !current.isEmpty { parts.append(current.joined(separator: paragraphSeparator)) }
            current = []
            currentLength = 0
        }
        func add(_ piece: String) {
            let added = current.isEmpty ? piece.count : piece.count + paragraphSeparator.count
            if currentLength + added > limit { flush() }
            currentLength += current.isEmpty ? piece.count : piece.count + paragraphSeparator.count
            current.append(piece)
        }

        for paragraph in paragraphs {
            if paragraph.count <= limit {
                add(paragraph)
                continue
            }
            // Too long for one part: split at sentences. Fill the current part first, then new parts.
            var fragment = ""
            func budget() -> Int { current.isEmpty ? limit : limit - currentLength - paragraphSeparator.count }
            for sentence in sentences(in: paragraph).flatMap({ $0.count > limit ? splitOverlong($0, limit: limit) : [$0] }) {
                let candidate = fragment.isEmpty ? sentence : fragment + " " + sentence
                if candidate.count <= budget() {
                    fragment = candidate
                } else if fragment.isEmpty {
                    flush()
                    fragment = sentence
                } else {
                    add(fragment)
                    flush()
                    fragment = sentence
                }
            }
            // The last fragment can share a part with the paragraphs after it.
            if !fragment.isEmpty { add(fragment) }
        }
        flush()
        return parts
    }

    /// Sentences, trimmed, in order.
    static func sentences(in paragraph: String) -> [String] {
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = paragraph
        var result: [String] = []
        tokenizer.enumerateTokens(in: paragraph.startIndex..<paragraph.endIndex) { range, _ in
            let s = paragraph[range].trimmingCharacters(in: .whitespacesAndNewlines)
            if !s.isEmpty { result.append(s) }
            return true
        }
        return result.isEmpty ? [paragraph] : result
    }

    /// The only case that can't respect sentence boundaries: a single sentence longer than the limit.
    /// It breaks after the last clause mark (; : ,) that fits, else the last space.
    private static func splitOverlong(_ sentence: String, limit: Int) -> [String] {
        var rest = Substring(sentence)
        var pieces: [String] = []
        while rest.count > limit {
            let window = rest.prefix(limit)
            let cut = window.lastIndex(where: { ";:,".contains($0) }).map { window.index(after: $0) }
                ?? window.lastIndex(of: " ")
                ?? window.endIndex
            pieces.append(String(rest[..<cut]).trimmingCharacters(in: .whitespaces))
            rest = rest[cut...].drop(while: { $0 == " " })
        }
        if !rest.isEmpty { pieces.append(String(rest)) }
        return pieces
    }

    private static func clean(_ s: String) -> String {
        s.replacingOccurrences(of: "\u{00A0}", with: " ")
            .replacingOccurrences(of: "[ \\t]+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// Turns raw extracted text into paragraphs (SPEC › Chunker step 1).
enum TextNormalizer {
    /// Plain text: paragraphs are separated by blank lines; single line breaks inside are unwrapped.
    static func paragraphs(fromPlainText text: String) -> [String] {
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        return normalized.components(separatedBy: "\n\n")
            .map { unwrap(dehyphenate($0)) }
            .filter { !$0.isEmpty }
    }

    /// PDF pages (`PDFPage.string`): drop running headers/footers and page numbers, fix hyphenation across
    /// line breaks, and rebuild paragraphs from wrapped lines.
    static func paragraphs(fromPDFPages pages: [String]) -> [String] {
        let pageLines = pages.map { page in
            page.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
                .components(separatedBy: "\n")
                .map { $0.trimmingCharacters(in: .whitespaces) }
        }
        let repeated = runningLines(in: pageLines)

        var lines: [String] = []
        for page in pageLines {
            let nonEmpty = page.enumerated().filter { !$0.element.isEmpty }
            let edges = Set(nonEmpty.prefix(2).map(\.offset) + nonEmpty.suffix(2).map(\.offset))
            for (i, line) in page.enumerated() {
                if edges.contains(i), isPageNumber(line) || repeated.contains(signature(line)) { continue }
                lines.append(line)
            }
            lines.append("") // Page ends are soft; the paragraph logic below decides.
        }

        // Median line length, to tell a paragraph's short last line from a wrapped one.
        let lengths = lines.filter { !$0.isEmpty }.map(\.count).sorted()
        let median = lengths.isEmpty ? 60 : lengths[lengths.count / 2]

        var paragraphs: [String] = []
        var current = ""
        var previousLine = ""
        for line in lines {
            if line.isEmpty {
                // A blank line ends a paragraph only when the text before it looks finished.
                if endsSentence(previousLine) && previousLine.count < Int(Double(median) * 0.8) || current.isEmpty {
                    if !current.isEmpty { paragraphs.append(current) }
                    current = ""
                }
                continue
            }
            if current.isEmpty {
                current = line
            } else if current.hasSuffix("-"), let first = line.first, first.isLowercase {
                current = String(current.dropLast()) + line // exam-\nple → example
            } else if endsSentence(previousLine) && previousLine.count < Int(Double(median) * 0.8) {
                paragraphs.append(current) // short last line: new paragraph
                current = line
            } else {
                current += " " + line
            }
            previousLine = line
        }
        if !current.isEmpty { paragraphs.append(current) }
        return paragraphs.map { $0.replacingOccurrences(of: "  +", with: " ", options: .regularExpression) }
    }

    /// Lines (digits ignored) that start or end most pages: running heads and feet.
    static func runningLines(in pages: [[String]]) -> Set<String> {
        guard pages.count >= 3 else { return [] }
        var counts: [String: Int] = [:]
        for page in pages {
            let nonEmpty = page.filter { !$0.isEmpty }
            let edgeLines = Set((nonEmpty.prefix(2) + nonEmpty.suffix(2)).map(signature))
            for s in edgeLines where !s.isEmpty { counts[s, default: 0] += 1 }
        }
        let threshold = max(3, Int((Double(pages.count) * 0.5).rounded(.up)))
        return Set(counts.filter { $0.value >= threshold }.keys)
    }

    static func signature(_ line: String) -> String {
        line.lowercased().replacingOccurrences(of: "[0-9ivxlc]+$|^[0-9ivxlc]+|[0-9]+", with: "#", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
    }

    static func isPageNumber(_ line: String) -> Bool {
        line.range(of: "^(page )?[0-9ivxlcdm]{1,6}( of [0-9]+)?$", options: [.regularExpression, .caseInsensitive]) != nil
    }

    static func dehyphenate(_ text: String) -> String {
        text.replacingOccurrences(of: "([a-z])-\\n([a-z])", with: "$1$2", options: .regularExpression)
    }

    static func unwrap(_ text: String) -> String {
        text.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }.joined(separator: " ")
    }

    private static func endsSentence(_ line: String) -> Bool {
        guard let last = line.last else { return false }
        return ".!?\"”’:)".contains(last)
    }
}
