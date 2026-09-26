import Foundation

/// A retrieved article the Brief may draw on.
struct RetrievedSource: Sendable, Equatable {
    var title: String
    var url: String
    var text: String
}

/// Wikipedia search → top article extracts (SPEC › Brief pipeline, retrieval).
enum WikipediaRetrieval {
    private static let api = URL(string: "https://en.wikipedia.org/w/api.php")!

    static func search(_ query: String, limit: Int = 3) async throws -> [RetrievedSource] {
        var search = URLComponents(url: api, resolvingAgainstBaseURL: false)!
        search.queryItems = [
            .init(name: "action", value: "query"), .init(name: "list", value: "search"), .init(name: "srsearch", value: query),
            .init(name: "srlimit", value: String(limit)), .init(name: "format", value: "json"),
        ]
        let found = try await get(search.url!)
        let titles = (((found["query"] as? [String: Any])?["search"] as? [[String: Any]]) ?? []).compactMap { $0["title"] as? String }
        guard !titles.isEmpty else { return [] }

        var extracts = URLComponents(url: api, resolvingAgainstBaseURL: false)!
        extracts.queryItems = [
            .init(name: "action", value: "query"), .init(name: "prop", value: "extracts"), .init(name: "explaintext", value: "1"),
            .init(name: "exchars", value: "6000"), .init(name: "redirects", value: "1"), .init(name: "format", value: "json"),
            .init(name: "titles", value: titles.joined(separator: "|")),
        ]
        let pages = ((try await get(extracts.url!)["query"] as? [String: Any])?["pages"] as? [String: [String: Any]]) ?? [:]
        let byTitle = Dictionary(pages.values.compactMap { page -> (String, String)? in
            guard let t = page["title"] as? String, let e = page["extract"] as? String, e.count > 200 else { return nil }
            return (t, e)
        }, uniquingKeysWith: { a, _ in a })
        return titles.compactMap { t in
            byTitle[t].map { RetrievedSource(title: t, url: "https://en.wikipedia.org/wiki/" + t.replacingOccurrences(of: " ", with: "_"), text: $0) }
        }
    }

    private static func get(_ url: URL) async throws -> [String: Any] {
        var request = URLRequest(url: url)
        request.setValue("Folio/0.1 (macOS reading app)", forHTTPHeaderField: "User-Agent")
        let (data, _) = try await URLSession.shared.data(for: request)
        return (try JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    }
}

/// A Brief ready to store.
struct DraftBrief: Sendable, Equatable {
    var angle: String
    var title: String
    var standfirst: String
    var body: String
    var sources: [BriefSource]
}

/// angle → retrieve → write (grounded) → validate, retrying once (SPEC › Brief pipeline).
/// Returns nil when there are no sources or the draft fails validation twice: no Brief then.
enum BriefPipeline {
    static func run(topic: String, pastAngles: [String], deeper: String?, limit: Int = Chunker.defaultLimit,
                    provider: any AIProvider,
                    retrieve: @Sendable (String) async throws -> [RetrievedSource] = { try await WikipediaRetrieval.search($0) }) async throws -> DraftBrief? {
        let plan = try await provider.complete(Prompts.briefAngle(topic: topic, pastAngles: pastAngles, deeper: deeper))
        let json = Prompts.jsonObject(in: plan)
        let angle = (json?["angle"] as? String) ?? topic
        let query = (json?["query"] as? String) ?? topic

        var sources = try await retrieve(query)
        if sources.isEmpty, query != topic { sources = try await retrieve(topic) }
        guard !sources.isEmpty else { return nil }

        var feedback: String?
        for _ in 0..<2 {
            let reply = try await provider.complete(Prompts.briefWrite(topic: topic, angle: angle, sources: sources, limit: limit, feedback: feedback))
            switch validate(reply, sources: sources, limit: limit) {
            case .success(let draft):
                return DraftBrief(angle: angle, title: draft.title, standfirst: draft.standfirst, body: draft.body, sources: draft.sources)
            case .failure(let problem):
                feedback = problem.message
            }
        }
        return nil
    }

    struct Problem: Error, Equatable { var message: String }

    /// Length ≤ limit, and every listed source is one it was given.
    static func validate(_ reply: String, sources: [RetrievedSource], limit: Int) -> Result<DraftBrief, Problem> {
        guard let json = Prompts.jsonObject(in: reply) else { return .failure(Problem(message: "The reply wasn't the JSON object asked for.")) }
        let title = (json["title"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let standfirst = (json["standfirst"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let body = (json["body"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, !body.isEmpty else { return .failure(Problem(message: "Title and body are required.")) }
        let total = title.count + standfirst.count + body.count
        guard total <= limit else { return .failure(Problem(message: "It was \(total) characters; the limit is \(limit).")) }

        let cited = (json["sources"] as? [Any] ?? []).compactMap { ($0 as? Int) ?? Int("\($0)") }
        guard !cited.isEmpty else { return .failure(Problem(message: "List the sources you used.")) }
        guard cited.allSatisfy({ (1...sources.count).contains($0) }) else {
            return .failure(Problem(message: "It cited a source that wasn't provided. Use only sources 1–\(sources.count)."))
        }
        let year = String(Calendar.current.component(.year, from: .now))
        let used = Array(Set(cited)).sorted().map { i in
            let s = sources[i - 1]
            return BriefSource(title: s.title, url: s.url, publisher: "Wikipedia", year: year)
        }
        return .success(DraftBrief(angle: "", title: title, standfirst: standfirst, body: body, sources: used))
    }
}
