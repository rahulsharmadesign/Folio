import Foundation
import Testing
@testable import Folio

private final class BundleToken {}
private func fixture(_ name: String, _ ext: String) -> URL {
    Bundle(for: BundleToken.self).url(forResource: name, withExtension: ext)!
}

struct ChunkerTests {
    private func paragraphs(_ count: Int, length: Int) -> [String] {
        (0..<count).map { i in
            var s = "Paragraph \(i) begins here."
            while s.count < length { s += " It goes on a little further." }
            return s
        }
    }

    @Test(arguments: [800, 1500, 2200])
    func partsNeverPassTheLimit(limit: Int) {
        let chapters = [SourceChapter(title: "One", paragraphs: paragraphs(30, length: 420))]
        let parts = Chunker.chunk(chapters, limit: limit)
        #expect(!parts.isEmpty)
        #expect(parts.allSatisfy { $0.text.count <= limit })
    }

    @Test func wholeParagraphsAreKeptTogether() {
        let source = paragraphs(12, length: 500)
        let parts = Chunker.chunk([SourceChapter(title: "One", paragraphs: source)])
        let rebuilt = parts.flatMap { $0.text.components(separatedBy: "\n\n") }
        #expect(rebuilt == source)
    }

    @Test func longParagraphsSplitAtSentencesNeverMidSentence() {
        let long = (1...80).map { "Sentence \($0) says something short." }.joined(separator: " ")
        let parts = Chunker.chunk([SourceChapter(title: "Long", paragraphs: [long])], limit: 800)
        #expect(parts.count > 1)
        for part in parts {
            #expect(part.text.count <= 800)
            #expect(part.text.hasPrefix("Sentence"))
            #expect(part.text.hasSuffix("short."))
        }
        #expect(parts.map(\.text).joined(separator: " ") == long)
    }

    @Test func aLongParagraphFillsThePartBeforeIt() {
        let intro = "A short opening paragraph."
        let long = (1...80).map { "Sentence \($0) says something short." }.joined(separator: " ")
        let parts = Chunker.chunk([SourceChapter(title: "One", paragraphs: [intro, long])], limit: 800)
        #expect(parts[0].text.hasPrefix(intro))
        #expect(parts[0].text.count > 600)
    }

    @Test func partsNeverCrossChapters() {
        let chapters = [
            SourceChapter(title: "One", paragraphs: ["Short one."]),
            SourceChapter(title: "Two", paragraphs: ["Short two.", "Another."]),
        ]
        let parts = Chunker.chunk(chapters)
        #expect(parts.map(\.chapterTitle) == ["One", "Two"])
        #expect(parts[0].text == "Short one.")
        #expect(parts.map(\.index) == [0, 1])
    }

    @Test func isDeterministic() {
        let chapters = [SourceChapter(title: "One", paragraphs: paragraphs(20, length: 700))]
        #expect(Chunker.chunk(chapters, limit: 1200) == Chunker.chunk(chapters, limit: 1200))
    }

    @Test func limitIsClampedToTheUserRange() {
        let chapters = [SourceChapter(title: "One", paragraphs: paragraphs(10, length: 300))]
        #expect(Chunker.chunk(chapters, limit: 100).allSatisfy { $0.text.count <= 800 })
        #expect(Chunker.chunk(chapters, limit: 100) == Chunker.chunk(chapters, limit: 800))
    }

    @Test func anOverlongSentenceBreaksAtAClause() {
        let sentence = Array(repeating: "and on it went, clause after clause", count: 80).joined(separator: ", ") + "."
        let parts = Chunker.chunk([SourceChapter(title: "", paragraphs: [sentence])], limit: 800)
        #expect(parts.allSatisfy { $0.text.count <= 800 })
        #expect(parts.dropLast().allSatisfy { $0.text.hasSuffix(",") })
    }
}

struct NormalizerTests {
    @Test func plainTextUnwrapsAndDehyphenates() throws {
        let text = try String(contentsOf: fixture("sample", "txt"), encoding: .utf8)
        let paragraphs = TextNormalizer.paragraphs(fromPlainText: text)
        #expect(paragraphs.count == 3)
        #expect(paragraphs[0] == "The first paragraph of plain text wraps over a hard line break, as old text files do.")
        #expect(paragraphs[1].contains("hyphenated word"))
    }

    @Test func pdfRunningHeadersAndPageNumbersAreDropped() {
        let bodies = ["The river ran slow under the bridge.", "Nobody had walked there for years.", "The orchards were heavy with fruit.", "Evenings came in early and blue."]
        let pages = bodies.enumerated().map { i, body in "THE BOOK TITLE\n\(body)\nIt was quiet, and the day went on.\nMore text in the middle of page \(i + 1).\nThe page ends with this line.\n\(i + 1)" }
        let paragraphs = TextNormalizer.paragraphs(fromPDFPages: pages)
        let all = paragraphs.joined(separator: " ")
        #expect(!all.contains("THE BOOK TITLE"))
        #expect(!all.contains(" 3 "))
        #expect(all.contains("Nobody had walked there for years."))
    }
}

struct ImporterTests {
    @Test func epubFollowsTheSpineAndSkipsNavigation() throws {
        let book = try EPUBImporter.read(fixture("sample", "epub"))
        #expect(book.title == "The Fixture Book")
        #expect(book.author == "A. Tester")
        #expect(book.chapters.map(\.title) == ["The First Chapter", "The Second Chapter"])
        #expect(book.chapters[0].paragraphs.first == "It was a bright cold day in the fixture, and the clocks were striking thirteen.")
        #expect(!book.chapters.flatMap(\.paragraphs).contains { $0.contains("Contents") })
    }

    @Test func epubChunksIntoPartsOfTwoThousandTwoHundredOrLess() throws {
        let book = try EPUBImporter.read(fixture("sample", "epub"))
        let parts = Chunker.chunk(book.chapters)
        #expect(parts.count >= 3) // the 3,800-character paragraph needs splitting
        #expect(parts.allSatisfy { $0.text.count <= 2200 })
        #expect(parts.allSatisfy { !$0.text.isEmpty })
    }

    @Test func protectedEpubIsRefusedPolitely() {
        #expect(throws: ImportError.protected) { try EPUBImporter.read(fixture("protected", "epub")) }
    }

    @Test func fontObfuscationIsNotDRM() {
        let xml = """
        <encryption xmlns="urn:oasis:names:tc:opendocument:xmlns:container" xmlns:enc="http://www.w3.org/2001/04/xmlenc#">
        <enc:EncryptedData><enc:CipherData><enc:CipherReference URI="OEBPS/fonts/a.otf"/></enc:CipherData></enc:EncryptedData></encryption>
        """
        #expect(!EPUBImporter.isDRM(xml))
    }

    @Test func pdfNormalisesHeadersHyphensAndPageBreaks() throws {
        let book = try PDFImporter.read(fixture("sample", "pdf"))
        #expect(book.title == "PDF Fixture")
        let text = book.chapters.flatMap(\.paragraphs).joined(separator: "\n")
        #expect(!text.contains("A FIXTURE BOOK"))
        #expect(text.contains("an example of a place forgotten."))
        #expect(text.contains("continues onto the next page without a break in the middle of its sentence"))
        #expect(!text.contains("\n2\n"))
    }

    @Test func bundledWaldenImports() throws {
        guard let url = Bundle.main.url(forResource: SampleContent.waldenResource, withExtension: "epub") else {
            Issue.record("walden.epub isn't in the app bundle")
            return
        }
        let book = try EPUBImporter.read(url)
        #expect(book.author == "Henry David Thoreau")
        #expect(book.chapters.first?.title == "Economy")
        #expect(book.chapters.contains { $0.title == "Where I Lived, and What I Lived For" })
        let all = book.chapters.flatMap(\.paragraphs).joined()
        #expect(!all.contains("Project Gutenberg License"))
        #expect(Chunker.chunk(book.chapters).allSatisfy { $0.text.count <= 2200 })
    }
}

struct PDFRepairTests {
    @Test func curlyQuoteLineBreaksAreJoined() {
        let raw = "life I’\nve lived. It’\ns\nnot so. Unconsciously, we\n’re all acting.\n“I went mad,\n” he said."
        #expect(TextNormalizer.repairPDFText(raw) == "life I’ve lived. It’s\nnot so. Unconsciously, we’re all acting.\n“I went mad,” he said.")
        #expect(TextNormalizer.repairPDFText("imitation of somebody else\n’\ns life with perfection.") == "imitation of somebody else’s life with perfection.")
    }

    @Test func aQuoteEndingAParagraphStaysAnEnding() {
        let paragraphs = TextNormalizer.paragraphs(fromPDFPages: [TextNormalizer.repairPDFText("He said “stop.”\nThe next day began.")])
        #expect(paragraphs.count >= 1)
        #expect(!paragraphs.joined().contains("’ve"))
    }

    @Test @MainActor func unmappedLigaturesBecomeRealWords() {
        let words: Set<String> = ["different", "benefits", "find", "office"]
        var cache: [String: String] = [:]
        let fixed = LigatureRepair.repair("di\u{0}erent bene\u{0}ts, \u{0}nd the o\u{0}ce", isWord: { words.contains($0) }, cache: &cache)
        #expect(fixed == "different benefits, find the office")
    }

    @Test @MainActor func theSpellCheckerKnowsCommonLigatureWords() {
        var cache: [String: String] = [:]
        #expect(LigatureRepair.repair("di\u{0}erent \u{0}nd", cache: &cache) == "different find")
    }
}
