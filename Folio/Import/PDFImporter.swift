import AppKit
import PDFKit

/// PDF → chapters: `page.string` per page → `TextNormalizer` (SPEC › Import).
/// Chapters follow the PDF outline when it has one; otherwise the whole document is one chapter.
enum PDFImporter {
    static func read(_ url: URL) throws -> ImportedBook {
        guard let document = PDFDocument(url: url) else { throw ImportError.unreadable }
        if document.isEncrypted && document.isLocked { throw ImportError.protected }

        let pages = (0..<document.pageCount).map { TextNormalizer.repairPDFText(document.page(at: $0)?.string ?? "") }
        guard pages.contains(where: { $0.trimmingCharacters(in: .whitespacesAndNewlines).count > 20 }) else {
            throw ImportError.noText
        }

        let attributes = document.documentAttributes ?? [:]
        let fileTitle = url.deletingPathExtension().lastPathComponent
        let title = (attributes[PDFDocumentAttribute.titleAttribute] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? fileTitle
        let author = attributes[PDFDocumentAttribute.authorAttribute] as? String ?? ""

        let starts = outlineStarts(document)
        var chapters: [SourceChapter] = []
        if starts.isEmpty {
            chapters = [SourceChapter(title: "", paragraphs: TextNormalizer.paragraphs(fromPDFPages: pages))]
        } else {
            // Front matter before the first outline entry is kept as an untitled chapter.
            let bounds = (starts.first?.page ?? 0) > 0 ? [(title: "", page: 0)] + starts : starts
            for (i, start) in bounds.enumerated() {
                let end = i + 1 < bounds.count ? bounds[i + 1].page : pages.count
                guard start.page < end else { continue }
                let paragraphs = TextNormalizer.paragraphs(fromPDFPages: Array(pages[start.page..<end]))
                chapters.append(SourceChapter(title: start.title, paragraphs: paragraphs))
            }
        }
        chapters = EPUBImporter.mergeTiny(chapters)
        guard chapters.contains(where: { !$0.paragraphs.isEmpty }) else { throw ImportError.noText }
        return ImportedBook(title: title, author: author, chapters: chapters)
    }

    /// Top-level outline entries with the page each starts on, in page order.
    private static func outlineStarts(_ document: PDFDocument) -> [(title: String, page: Int)] {
        guard let root = document.outlineRoot, root.numberOfChildren > 0 else { return [] }
        var starts: [(title: String, page: Int)] = []
        for i in 0..<root.numberOfChildren {
            guard let item = root.child(at: i), let page = item.destination?.page else { continue }
            let index = document.index(for: page)
            starts.append((item.label ?? "", index))
        }
        return starts.sorted { $0.page < $1.page }.reduce(into: []) { acc, s in
            if acc.last?.page != s.page { acc.append(s) }
        }
    }
}

/// PDFKit leaves ligatures it can't map (ff, fi, fl, ffi, ffl) as NUL. The spell checker picks the letters that
/// make a real word. Main actor: `NSSpellChecker` is AppKit.
@MainActor
enum LigatureRepair {
    static let candidates = ["fi", "ff", "fl", "ffi", "ffl"]

    static func repair(_ book: ImportedBook) -> ImportedBook {
        guard book.chapters.contains(where: { $0.paragraphs.contains { $0.contains("\u{0}") } }) else { return book }
        var cache: [String: String] = [:]
        var out = book
        for c in out.chapters.indices {
            out.chapters[c].paragraphs = out.chapters[c].paragraphs.map { paragraph in
                guard paragraph.contains("\u{0}") else { return paragraph }
                return repair(paragraph, cache: &cache)
            }
        }
        return out
    }

    static func repair(_ text: String, isWord: @MainActor (String) -> Bool = isEnglishWord, cache: inout [String: String]) -> String {
        let ns = text as NSString
        let regex = try! NSRegularExpression(pattern: "[\\p{L}\\u0000]*\\u0000[\\p{L}\\u0000]*")
        var result = ""
        var last = 0
        for match in regex.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            let word = ns.substring(with: match.range)
            let fixed = cache[word] ?? {
                let pick = candidates.lazy.map { word.replacingOccurrences(of: "\u{0}", with: $0) }.first(where: isWord)
                return pick ?? word.replacingOccurrences(of: "\u{0}", with: "fi")
            }()
            cache[word] = fixed
            result += ns.substring(with: NSRange(location: last, length: match.range.location - last)) + fixed
            last = NSMaxRange(match.range)
        }
        result += ns.substring(from: last)
        return result.replacingOccurrences(of: "\u{0}", with: "fi")
    }

    static func isEnglishWord(_ word: String) -> Bool {
        NSSpellChecker.shared.checkSpelling(of: word, startingAt: 0, language: "en", wrap: false,
                                            inSpellDocumentWithTag: 0, wordCount: nil).location == NSNotFound
    }
}
