import Foundation
import PDFKit

/// PDF → chapters: `page.string` per page → `TextNormalizer` (SPEC › Import).
/// Chapters follow the PDF outline when it has one; otherwise the whole document is one chapter.
enum PDFImporter {
    static func read(_ url: URL) throws -> ImportedBook {
        guard let document = PDFDocument(url: url) else { throw ImportError.unreadable }
        if document.isEncrypted && document.isLocked { throw ImportError.protected }

        let pages = (0..<document.pageCount).map { document.page(at: $0)?.string ?? "" }
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
