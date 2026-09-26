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

    /// The serial passage slots draw from: the one marked current, else the oldest active one.
    var currentWork: Work? {
        let all = works()
        return all.first { $0.isCurrent && $0.status == .active } ?? all.first { $0.status == .active }
    }

    func setCurrent(_ work: Work) {
        for w in works() { w.isCurrent = (w.id == work.id) }
        if work.status == .paused { work.status = .active }
        save()
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
                let book = try await Self.parse(destination, ext: ext)
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
        if currentWork == nil || count == 0 { work.isCurrent = true }
        save()
        return work
    }

    func remove(_ work: Work) {
        if let name = work.fileName, let dir = try? Self.libraryDirectory() {
            try? FileManager.default.removeItem(at: dir.appendingPathComponent(name))
        }
        let wasCurrent = work.isCurrent
        context.delete(work)
        save()
        if wasCurrent, let next = currentWork { setCurrent(next) }
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
            let work = insert(book, source: .sample, fileName: nil, limit: limit, title: SampleContent.waldenTitle)
            work.cadenceHint = "Mornings"
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

    // MARK: Edition length

    /// Re-chunks every serial's unread parts at a new limit (Schedule › Edition length).
    /// Read parts are history and stay as they were.
    func rechunkUnread(limit: Int) {
        for work in works() {
            let unread = work.sortedParts.filter { $0.index >= work.nextPartIndex }
            guard !unread.isEmpty else { continue }
            var chapters: [SourceChapter] = []
            for part in unread {
                let paragraphs = part.text.components(separatedBy: Chunker.paragraphSeparator)
                if chapters.last?.title == part.chapterTitle {
                    chapters[chapters.count - 1].paragraphs += paragraphs
                } else {
                    chapters.append(SourceChapter(title: part.chapterTitle, paragraphs: paragraphs))
                }
            }
            let chunks = Chunker.chunk(chapters, limit: limit)
            // Skip the work if nothing would change.
            if chunks.map(\.text) == unread.map(\.text) { continue }
            for part in unread { context.delete(part) }
            for chunk in chunks {
                let part = Part(index: work.nextPartIndex + chunk.index, text: chunk.text, chapterTitle: chunk.chapterTitle)
                part.work = work
                context.insert(part)
            }
        }
        save()
    }
}
