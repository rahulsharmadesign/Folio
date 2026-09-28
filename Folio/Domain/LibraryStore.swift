import Foundation
import Observation
import SwiftData
import UniformTypeIdentifiers

/// Imports, samples and serial bookkeeping on top of SwiftData. Main-actor: it owns the main context.
@MainActor @Observable
final class LibraryStore {
    let context: ModelContext
    var isImporting = false
    /// A message for the last failed import (shown as an alert).
    var importError: String?

    init(context: ModelContext) {
        self.context = context
    }

    static let washes = ["wc-lapis", "wc-plum", "wc-rose", "wc-sage", "wc-ochre"]
    static let supportedTypes: [UTType] = [UTType("org.idpf.epub-container") ?? .epub, .pdf]

    // MARK: Queries

    func works() -> [Work] {
        (try? context.fetch(FetchDescriptor<Work>(sortBy: [SortDescriptor(\.addedAt)]))) ?? []
    }

    /// The book to continue: the unfinished one read most recently, else the newest one added.
    var currentWork: Work? {
        works().filter { !$0.isFinished && $0.partCount > 0 }.max { ($0.lastReadAt ?? $0.addedAt) < ($1.lastReadAt ?? $1.addedAt) }
    }

    func feeds() -> [NewsFeed] {
        (try? context.fetch(FetchDescriptor<NewsFeed>(sortBy: [SortDescriptor(\.createdAt)]))) ?? []
    }

    func quotes() -> [FavoriteQuote] {
        (try? context.fetch(FetchDescriptor<FavoriteQuote>(sortBy: [SortDescriptor(\.createdAt)]))) ?? []
    }

    func topics() -> [Topic] {
        (try? context.fetch(FetchDescriptor<Topic>(sortBy: [SortDescriptor(\.createdAt)]))) ?? []
    }

    func save() {
        try? context.save()
    }

    // MARK: Import

    static func libraryDirectory() throws -> URL {
        let dir = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("Folio/Library", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Copies the file into the container (so it survives the sandbox), parses it off the main thread,
    /// chunks it and stores the serial.
    @discardableResult
    func importFile(at url: URL, limit: Int) async -> Work? {
        isImporting = true
        defer { isImporting = false }
        let ext = url.pathExtension.lowercased()
        guard ext == "epub" || ext == "pdf" else {
            importError = ImportError.unsupported.localizedDescription
            return nil
        }
        do {
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            let name = UUID().uuidString + "." + ext
            let destination = try Self.libraryDirectory().appendingPathComponent(name)
            try FileManager.default.copyItem(at: url, to: destination)
            do {
                let book = LigatureRepair.repair(try await Self.parse(destination, ext: ext))
                return insert(book, source: .upload, fileName: name, limit: limit)
            } catch {
                try? FileManager.default.removeItem(at: destination)
                throw error
            }
        } catch {
            importError = (error as? LocalizedError)?.errorDescription ?? ImportError.unreadable.localizedDescription
            return nil
        }
    }

    nonisolated static func parse(_ url: URL, ext: String) async throws -> ImportedBook {
        try await Task.detached(priority: .userInitiated) {
            ext == "pdf" ? try PDFImporter.read(url) : try EPUBImporter.read(url)
        }.value
    }

    @discardableResult
    private func insert(_ book: ImportedBook, source: WorkSource, fileName: String?, limit: Int, title: String? = nil) -> Work {
        let count = works().count
        let work = Work(title: title ?? book.title, author: book.author, source: source, fileName: fileName,
                        coverWash: Self.washes[count % Self.washes.count])
        context.insert(work)
        for chunk in Chunker.chunk(book.chapters, limit: limit) {
            let part = Part(index: chunk.index, text: chunk.text, chapterTitle: chunk.chapterTitle)
            part.work = work
            context.insert(part)
        }
        save()
        return work
    }

    func remove(_ work: Work) {
        if let name = work.fileName, let dir = try? Self.libraryDirectory() {
            try? FileManager.default.removeItem(at: dir.appendingPathComponent(name))
        }
        context.delete(work)
        save()
    }

    // MARK: Samples

    private static let seededKey = "FolioSeededSamples"

    /// First launch: Walden as a serial, the sample Brief and its topic.
    func seedSamplesIfNeeded(limit: Int, force: Bool = false) async {
        if !force {
            guard !UserDefaults.standard.bool(forKey: Self.seededKey) else { return }
            UserDefaults.standard.set(true, forKey: Self.seededKey)
        }

        if let url = Bundle.main.url(forResource: SampleContent.waldenResource, withExtension: "epub"),
           let book = try? await Self.parse(url, ext: "epub") {
            insert(book, source: .sample, fileName: nil, limit: limit, title: SampleContent.waldenTitle)
        }
        let topic = Topic(label: SampleContent.briefTopic)
        topic.pastAngles = ["How honeybee swarms choose a nest site"]
        context.insert(topic)
        let s = SampleContent.brief
        let body = s.body.split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }.joined(separator: "\n")
        context.insert(Brief(topicLabel: SampleContent.briefTopic, title: s.title, standfirst: s.standfirst, body: body, sources: s.sources, isSample: true))
        save()
    }

    // MARK: Import fixes

    private static let pdfTextVersionKey = "FolioPDFTextVersion"
    /// Bump when PDF text extraction changes; uploaded PDFs are re-read once, keeping the reader's place.
    static let pdfTextVersion = 4

    func refreshImportedPDFsIfNeeded(limit: Int) async {
        guard UserDefaults.standard.integer(forKey: Self.pdfTextVersionKey) < Self.pdfTextVersion,
              let dir = try? Self.libraryDirectory() else { return }
        for work in works() where work.source == .upload {
            guard let name = work.fileName, name.lowercased().hasSuffix(".pdf"),
                  let parsed = try? await Self.parse(dir.appendingPathComponent(name), ext: "pdf") else { continue }
            let book = LigatureRepair.repair(parsed)
            // Keep the place by how far through the text the reader was.
            let old = work.sortedParts
            let total = max(1, old.reduce(0) { $0 + $1.charCount })
            let readChars = old.prefix(work.nextPartIndex).reduce(0) { $0 + $1.charCount }
            let wasFinished = work.isFinished
            for part in old { context.delete(part) }
            let chunks = Chunker.chunk(book.chapters, limit: limit)
            let newTotal = max(1, chunks.reduce(0) { $0 + $1.text.count })
            var position = 0, running = 0
            for chunk in chunks {
                let part = Part(index: chunk.index, text: chunk.text, chapterTitle: chunk.chapterTitle)
                part.work = work
                context.insert(part)
                if running * total <= readChars * newTotal { position = chunk.index } // the part holding the place
                running += chunk.text.count
            }
            work.nextPartIndex = wasFinished ? chunks.count : min(position, max(0, chunks.count - 1))
        }
        save()
        // Only once the new text is saved, so an interrupted run is simply redone next launch.
        UserDefaults.standard.set(Self.pdfTextVersion, forKey: Self.pdfTextVersionKey)
    }

    // MARK: News feeds

    private static let seededFeedsKey = "FolioSeededFeeds"

    /// The Tech news Brief's starting feeds; the user can remove them and add their own (Library).
    static let defaultFeeds: [(url: String, title: String)] = [
        ("https://feeds.arstechnica.com/arstechnica/technology-lab", "Ars Technica"),
        ("https://www.theverge.com/rss/index.xml", "The Verge"),
        ("https://techcrunch.com/feed/", "TechCrunch"),
        ("https://www.technologyreview.com/feed/", "MIT Technology Review"),
    ]

    func seedFeedsIfNeeded(force: Bool = false) {
        if !force {
            guard !UserDefaults.standard.bool(forKey: Self.seededFeedsKey) else { return }
            UserDefaults.standard.set(true, forKey: Self.seededFeedsKey)
        }
        for feed in Self.defaultFeeds { context.insert(NewsFeed(url: feed.url, title: feed.title)) }
        save()
    }
}
