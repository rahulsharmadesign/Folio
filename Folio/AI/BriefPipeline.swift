import Foundation
import NaturalLanguage

/// What to write a Brief about (SPEC › What it is).
struct BriefRequest: Sendable {
    var kind: BriefKind
    /// `.topic`: the topic, in the reader's words.
    var topic = ""
    /// `.quote`: the reader's own quote and who said it, if they know. Empty: Folio picks one.
    var quote = ""
    var author = ""
    /// Angles, people or quotes already covered, to avoid.
    var past: [String] = []
    /// `.topic`: "Go deeper tomorrow".
    var deeper: String?
    /// `.news`: feed URLs, and item links earlier Briefs already used.
    var feeds: [String] = []
    var seenLinks: Set<String> = []
    var date = Date.now
}

/// Where each kind of Brief gets its sources. Injected so tests can run offline.
struct BriefRetrieval: Sendable {
    var wikipedia: @Sendable (String) async throws -> [RetrievedSource]
    var wikiquote: @Sendable (String) async throws -> [RetrievedSource]
    var news: @Sendable ([String], Set<String>) async throws -> [RetrievedSource]

    static let live = BriefRetrieval(
        wikipedia: { try await MediaWiki.wikipedia.search($0) },
        wikiquote: { try await MediaWiki.wikiquote.search($0, limit: 2, snippets: true) },
        news: { await FeedRetrieval.recent(from: $0, excluding: $1) })
}

/// A Brief ready to store.
struct DraftBrief: Sendable, Equatable {
    var angle: String
    var title: String
    var standfirst: String
    var body: String
    var sources: [BriefSource]
    /// The quote explained (or the angle), remembered so it isn't repeated.
    var subject = ""
}

/// plan → retrieve → write (grounded) → validate, retrying once (SPEC › Brief pipeline).
/// Returns nil when there are no sources or the draft fails validation twice: no Brief then.
enum BriefPipeline {
    static func run(_ request: BriefRequest, limit: Int = Chunker.defaultLimit, provider: any AIProvider,
                    retrieval: BriefRetrieval = .live) async throws -> DraftBrief? {
        let (angle, sources) = try await plan(request, provider: provider, retrieval: retrieval)
        guard !sources.isEmpty else { return nil }
        // A quote Folio picks itself must be one the sources actually contain.
        let picksQuote = request.kind == .quote && request.quote.isEmpty

        var feedback: String?
        for _ in 0..<2 {
            let reply = try await provider.complete(Prompts.briefWrite(request, angle: angle, sources: sources, limit: limit, feedback: feedback))
            switch validate(reply, sources: sources, limit: limit, quoteMustAppear: picksQuote) {
            case .success(var draft):
                draft.angle = angle
                if draft.subject.isEmpty { draft.subject = request.kind == .quote ? request.quote : angle }
                return draft
            case .failure(let problem):
                feedback = problem.message
            }
        }
        return nil
    }

    /// The angle to take and the sources to write from.
    private static func plan(_ r: BriefRequest, provider: any AIProvider, retrieval: BriefRetrieval) async throws -> (String, [RetrievedSource]) {
        switch r.kind {
        case .topic:
            let json = Prompts.jsonObject(in: try await provider.complete(Prompts.briefAngle(topic: r.topic, pastAngles: r.past, deeper: r.deeper)))
            let angle = (json?["angle"] as? String) ?? r.topic
            let query = (json?["query"] as? String) ?? r.topic
            var sources = try await retrieval.wikipedia(query)
            if sources.isEmpty, query != r.topic { sources = try await retrieval.wikipedia(r.topic) }
            return (angle, sources)

        case .story:
            let json = Prompts.jsonObject(in: try await provider.complete(Prompts.storyAngle(past: r.past)))
            guard let query = json?["query"] as? String, !query.isEmpty else { return ("", []) }
            return ((json?["angle"] as? String) ?? query, try await retrieval.wikipedia(query))

        case .quote:
            if !r.quote.isEmpty {
                // The reader's quote: where it appears on Wikiquote, and the speaker on Wikipedia.
                var sources = try await retrieval.wikiquote(r.quote)
                if sources.isEmpty, !r.author.isEmpty { sources = try await retrieval.wikiquote(r.author) }
                if !r.author.isEmpty { sources += try await retrieval.wikipedia(r.author).prefix(1) }
                return (r.quote, dedupe(sources))
            }
            let json = Prompts.jsonObject(in: try await provider.complete(Prompts.quotePerson(past: r.past)))
            guard let person = json?["person"] as? String, !person.isEmpty else { return ("", []) }
            let quotes = try await retrieval.wikiquote(person).prefix(1)
            guard !quotes.isEmpty else { return (person, []) }
            return (person, dedupe(Array(quotes) + (try await retrieval.wikipedia(person).prefix(1))))

        case .news:
            let items = try await retrieval.news(r.feeds, r.seenLinks)
            return ("Tech news, " + r.date.formatted(.dateTime.day().month(.wide)), items)
        }
    }

    private static func dedupe(_ sources: [RetrievedSource]) -> [RetrievedSource] {
        var seen = Set<String>()
        return sources.filter { seen.insert($0.url).inserted }
    }

    struct Problem: Error, Equatable { var message: String }

    /// Length ≤ limit, every listed source is one it was given, and (when Folio picked the quote)
    /// the quote appears in a source.
    static func validate(_ reply: String, sources: [RetrievedSource], limit: Int, quoteMustAppear: Bool = false) -> Result<DraftBrief, Problem> {
        guard let json = Prompts.jsonObject(in: reply) else { return .failure(Problem(message: "The reply wasn't the JSON object asked for.")) }
        let title = (json["title"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let standfirst = (json["standfirst"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let body = BriefParagraphs.ensure((json["body"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines))
        guard !title.isEmpty, !body.isEmpty else { return .failure(Problem(message: "Title and body are required.")) }
        let total = title.count + standfirst.count + body.count
        guard total <= limit else { return .failure(Problem(message: "It was \(total) characters; the limit is \(limit).")) }

        let cited = (json["sources"] as? [Any] ?? []).compactMap { ($0 as? Int) ?? Int("\($0)") }
        guard !cited.isEmpty else { return .failure(Problem(message: "List the sources you used.")) }
        guard cited.allSatisfy({ (1...sources.count).contains($0) }) else {
            return .failure(Problem(message: "It cited a source that wasn't provided. Use only sources 1–\(sources.count)."))
        }

        var subject = ""
        if quoteMustAppear {
            let quote = (json["quote"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard quote.count >= 12, sources.contains(where: { normalized($0.text).contains(normalized(quote)) }) else {
                return .failure(Problem(message: "The quote must be copied word for word from the Wikiquote source."))
            }
            subject = quote
        }

        let thisYear = String(Calendar.current.component(.year, from: .now))
        let used = Array(Set(cited)).sorted().map { i in
            let s = sources[i - 1]
            return BriefSource(title: s.title, url: s.url, publisher: s.publisher, year: s.year.isEmpty ? thisYear : s.year)
        }
        return .success(DraftBrief(angle: "", title: title, standfirst: standfirst, body: body, sources: used, subject: subject))
    }

    /// Letters and digits only, lowercased, so curly quotes and spacing don't matter.
    static func normalized(_ s: String) -> String {
        String(s.lowercased().unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }.map(Character.init))
    }
}

/// Briefs read as 3–6 short paragraphs. Models don't always break them, so a body that arrives as one block
/// is split at sentence ends, about three sentences a paragraph. Idempotent.
enum BriefParagraphs {
    static func ensure(_ body: String) -> String {
        guard !body.contains("\n\n") else { return body }
        if body.contains("\n") { return body.replacingOccurrences(of: "\\s*\\n\\s*", with: "\n\n", options: .regularExpression) }
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = body
        let sentences = tokenizer.tokens(for: body.startIndex..<body.endIndex).map { body[$0].trimmingCharacters(in: .whitespaces) }
        guard sentences.count > 3 else { return body }
        let perParagraph = max(2, Int((Double(sentences.count) / 4).rounded(.up)))
        return stride(from: 0, to: sentences.count, by: perParagraph)
            .map { sentences[$0..<min($0 + perParagraph, sentences.count)].joined(separator: " ") }
            .joined(separator: "\n\n")
    }
}
