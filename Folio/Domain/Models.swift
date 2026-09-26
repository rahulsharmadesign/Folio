import Foundation
import SwiftData

// SwiftData models (SPEC › Data model). Enums are stored as raw strings so the schema stays simple.

enum WorkKind: String, Codable, Sendable { case book, publication }
enum WorkSource: String, Codable, Sendable { case upload, gutenberg, sample, feed }
enum WorkStatus: String, Codable, Sendable { case active, paused, finished }

@Model
final class Work {
    @Attribute(.unique) var id: UUID
    var title: String
    var author: String
    var kindRaw: String
    var sourceRaw: String
    /// File name of the imported copy inside Application Support/Folio/Library.
    var fileName: String?
    /// Watercolour used for the cover (`wc-lapis` …).
    var coverWash: String
    var statusRaw: String
    /// "Mornings", "Sundays" — from the slot that serves it.
    var cadenceHint: String
    var addedAt: Date
    /// Index of the next unread part. Parts before it have been read.
    var nextPartIndex: Int
    /// The serial the passage slots draw from.
    var isCurrent: Bool
    @Relationship(deleteRule: .cascade, inverse: \Part.work) var parts: [Part] = []

    init(title: String, author: String, kind: WorkKind = .book, source: WorkSource, fileName: String?, coverWash: String) {
        id = UUID()
        self.title = title
        self.author = author
        kindRaw = kind.rawValue
        sourceRaw = source.rawValue
        self.fileName = fileName
        self.coverWash = coverWash
        statusRaw = WorkStatus.active.rawValue
        cadenceHint = ""
        addedAt = .now
        nextPartIndex = 0
        isCurrent = false
    }

    var kind: WorkKind { WorkKind(rawValue: kindRaw) ?? .book }
    var source: WorkSource { WorkSource(rawValue: sourceRaw) ?? .upload }
    var status: WorkStatus {
        get { WorkStatus(rawValue: statusRaw) ?? .active }
        set { statusRaw = newValue.rawValue }
    }

    var sortedParts: [Part] { parts.sorted { $0.index < $1.index } }
    var partCount: Int { parts.count }

    func part(at index: Int) -> Part? { parts.first { $0.index == index } }
    var nextPart: Part? { part(at: nextPartIndex) }
    var progress: Double { partCount == 0 ? 0 : Double(nextPartIndex) / Double(partCount) }
}

@Model
final class Part {
    var index: Int
    var text: String
    var chapterTitle: String
    /// "Previously", generated lazily by AI from the previous part.
    var recap: String?
    var charCount: Int
    var readAt: Date?
    var isBookmarked: Bool = false
    var work: Work?

    init(index: Int, text: String, chapterTitle: String) {
        self.index = index
        self.text = text
        self.chapterTitle = chapterTitle
        charCount = text.count
    }
}

@Model
final class Topic {
    @Attribute(.unique) var id: UUID
    /// The user's own words.
    var label: String
    var isActive: Bool
    var pastAngles: [String]
    /// Adaptive weight from More/Less like this (1 = neutral).
    var weight: Double
    /// Set by "Go deeper tomorrow": the next Brief continues this angle.
    var deeperAngle: String?
    var createdAt: Date

    init(label: String, isActive: Bool = true) {
        id = UUID()
        self.label = label
        self.isActive = isActive
        pastAngles = []
        weight = 1
        createdAt = .now
    }
}

struct BriefSource: Codable, Hashable, Sendable {
    var title: String
    var url: String
    var publisher: String
    var year: String
}

@Model
final class Brief {
    @Attribute(.unique) var id: UUID
    var topicLabel: String
    var title: String
    var standfirst: String
    var body: String
    var sourcesData: Data
    var createdAt: Date
    var readAt: Date?
    var isSample: Bool

    init(topicLabel: String, title: String, standfirst: String, body: String, sources: [BriefSource], isSample: Bool = false) {
        id = UUID()
        self.topicLabel = topicLabel
        self.title = title
        self.standfirst = standfirst
        self.body = body
        sourcesData = (try? JSONEncoder().encode(sources)) ?? Data()
        createdAt = .now
        self.isSample = isSample
    }

    var sources: [BriefSource] { (try? JSONDecoder().decode([BriefSource].self, from: sourcesData)) ?? [] }
    var charCount: Int { title.count + standfirst.count + body.count }
}

enum EditionKind: String, Codable, Sendable { case passage, brief }
enum EditionState: String, Codable, Sendable { case prepared, ready, read, replaced }

@Model
final class Edition {
    @Attribute(.unique) var id: UUID
    var slotID: String
    var scheduledFor: Date
    var kindRaw: String
    var part: Part?
    var brief: Brief?
    var stateRaw: String
    /// too easy / just right / a stretch
    var rating: String?

    init(slotID: String, scheduledFor: Date, kind: EditionKind, part: Part? = nil, brief: Brief? = nil) {
        id = UUID()
        self.slotID = slotID
        self.scheduledFor = scheduledFor
        kindRaw = kind.rawValue
        self.part = part
        self.brief = brief
        stateRaw = EditionState.prepared.rawValue
    }

    var kind: EditionKind { EditionKind(rawValue: kindRaw) ?? .passage }
    var state: EditionState {
        get { EditionState(rawValue: stateRaw) ?? .prepared }
        set { stateRaw = newValue.rawValue }
    }
}

enum HighlightKind: String, Codable, Sendable { case passage, brief }

@Model
final class Highlight {
    @Attribute(.unique) var id: UUID
    var text: String
    var kindRaw: String
    /// "Walden" / "The Brief"
    var sourceTitle: String
    /// "Where I Lived" / "History of cartography"
    var sourceDetail: String
    var workID: UUID?
    var partIndex: Int?
    /// Character range inside the part or Brief body, for drawing the marker.
    var rangeLocation: Int
    var rangeLength: Int
    var note: String?
    var createdAt: Date
    // Recall (spaced repetition: 4 d → 2 w → 1 m → 3 m).
    var recallStage: Int
    var nextReviewAt: Date?
    var kept: Bool

    init(text: String, kind: HighlightKind, sourceTitle: String, sourceDetail: String, workID: UUID?, partIndex: Int?,
         range: NSRange, note: String? = nil, now: Date = .now) {
        id = UUID()
        self.text = text
        kindRaw = kind.rawValue
        self.sourceTitle = sourceTitle
        self.sourceDetail = sourceDetail
        self.workID = workID
        self.partIndex = partIndex
        rangeLocation = range.location
        rangeLength = range.length
        self.note = note
        createdAt = now
        recallStage = 0
        nextReviewAt = Recall.firstReview(after: now)
        kept = true
    }

    var kind: HighlightKind { HighlightKind(rawValue: kindRaw) ?? .passage }
    var range: NSRange { NSRange(location: rangeLocation, length: rangeLength) }
}

@Model
final class Reflection {
    @Attribute(.unique) var id: UUID
    var prompt: String
    var answer: String?
    var sourceTitle: String
    var createdAt: Date

    init(prompt: String, answer: String?, sourceTitle: String) {
        id = UUID()
        self.prompt = prompt
        self.answer = answer
        self.sourceTitle = sourceTitle
        createdAt = .now
    }
}

enum FolioSchema {
    static let models: [any PersistentModel.Type] = [Work.self, Part.self, Topic.self, Brief.self, Edition.self, Highlight.self, Reflection.self]
}
