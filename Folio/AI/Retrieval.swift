import Foundation
import SwiftSoup

/// A retrieved article or news item the Brief may draw on.
struct RetrievedSource: Sendable, Equatable {
    var title: String
    var url: String
    var text: String
    var publisher = "Wikipedia"
    /// Publication year of a news item; empty means the year it was retrieved.
    var year = ""
}

/// MediaWiki search → top page extracts (SPEC › Brief pipeline, retrieval), for Wikipedia and Wikiquote.
struct MediaWiki: Sendable {
    var host: String
    var publisher: String

    static let wikipedia = MediaWiki(host: "en.wikipedia.org", publisher: "Wikipedia")
    static let wikiquote = MediaWiki(host: "en.wikiquote.org", publisher: "Wikiquote")

    private var api: URL { URL(string: "https://\(host)/w/api.php")! }

    /// `snippets` puts each page's search match first, so a quote found deep in a long page is still in the text.
    func search(_ query: String, limit: Int = 3, snippets: Bool = false) async throws -> [RetrievedSource] {
        var search = URLComponents(url: api, resolvingAgainstBaseURL: false)!
        search.queryItems = [
            .init(name: "action", value: "query"), .init(name: "list", value: "search"), .init(name: "srsearch", value: query),
            .init(name: "srlimit", value: String(limit)), .init(name: "format", value: "json"),
        ]
        let hits = (((try await Self.get(search.url!)["query"] as? [String: Any])?["search"] as? [[String: Any]]) ?? [])
        let titles = hits.compactMap { $0["title"] as? String }
        guard !titles.isEmpty else { return [] }
        let matches = Dictionary(hits.compactMap { hit -> (String, String)? in
            guard let t = hit["title"] as? String, let s = hit["snippet"] as? String else { return nil }
            return (t, HTMLText.plain(s))
        }, uniquingKeysWith: { a, _ in a })

        var extracts = URLComponents(url: api, resolvingAgainstBaseURL: false)!
        extracts.queryItems = [
            .init(name: "action", value: "query"), .init(name: "prop", value: "extracts"), .init(name: "explaintext", value: "1"),
            .init(name: "exchars", value: "6000"), .init(name: "redirects", value: "1"), .init(name: "format", value: "json"),
            .init(name: "titles", value: titles.joined(separator: "|")),
        ]
        let pages = ((try await Self.get(extracts.url!)["query"] as? [String: Any])?["pages"] as? [String: [String: Any]]) ?? [:]
        let byTitle = Dictionary(pages.values.compactMap { page -> (String, String)? in
            guard let t = page["title"] as? String, let e = page["extract"] as? String, e.count > 200 else { return nil }
            return (t, e)
        }, uniquingKeysWith: { a, _ in a })
        return titles.compactMap { t in
            byTitle[t].map { extract in
                let text = snippets ? "Search match: …\(matches[t] ?? "")…\n\n\(extract)" : extract
                return RetrievedSource(title: t, url: "https://\(host)/wiki/" + t.replacingOccurrences(of: " ", with: "_"), text: text, publisher: publisher)
            }
        }
    }

    private static func get(_ url: URL) async throws -> [String: Any] {
        var request = URLRequest(url: url)
        request.setValue("Folio/0.1 (macOS reading app)", forHTTPHeaderField: "User-Agent")
        let (data, _) = try await URLSession.shared.data(for: request)
        return (try JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    }
}

// MARK: News feeds

struct FeedItem: Sendable, Equatable {
    var title: String
    var link: String
    var summary: String
    var date: Date?
}

struct ParsedFeed: Sendable, Equatable {
    var title: String
    var items: [FeedItem]
}

/// RSS 2.0 and Atom, with `XMLParser`. Summaries come back as plain text.
final class FeedParser: NSObject, XMLParserDelegate {
    private var feedTitle = ""
    private var items: [FeedItem] = []
    private var current: [String: String]?
    /// One text buffer per open element; a closing element's text also flows into its parent (Atom xhtml content).
    private var buffers: [String] = []

    static func parse(_ data: Data) -> ParsedFeed? {
        let delegate = FeedParser()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        guard parser.parse() || !delegate.items.isEmpty else { return nil }
        return ParsedFeed(title: delegate.feedTitle, items: delegate.items)
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName: String?,
                attributes: [String: String] = [:]) {
        let name = elementName.lowercased()
        buffers.append("")
        if name == "item" || name == "entry" { current = [:] }
        // Atom: <link rel="alternate" href="…"/>
        if name == "link", current != nil, current?["link"] == nil, let href = attributes["href"],
           attributes["rel"] == nil || attributes["rel"] == "alternate" {
            current?["link"] = href
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if !buffers.isEmpty { buffers[buffers.count - 1] += string }
    }

    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
        if !buffers.isEmpty { buffers[buffers.count - 1] += String(decoding: CDATABlock, as: UTF8.self) }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName: String?) {
        let name = elementName.lowercased()
        let raw = buffers.popLast() ?? ""
        if !buffers.isEmpty { buffers[buffers.count - 1] += raw }
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)

        guard current != nil else {
            if name == "title", feedTitle.isEmpty { feedTitle = HTMLText.plain(value) }
            return
        }
        switch name {
        case "title":
            if current?["title"] == nil { current?["title"] = HTMLText.plain(value) }
        case "link":
            if current?["link"] == nil, !value.isEmpty { current?["link"] = value }
        case "description", "summary", "content:encoded", "content":
            // Keep the fullest body the feed offers.
            if value.count > (current?["summary"]?.count ?? 0) { current?["summary"] = value }
        case "pubdate", "published", "updated", "dc:date":
            if current?["date"] == nil { current?["date"] = value }
        case "item", "entry":
            if let c = current, let title = c["title"], !title.isEmpty, let link = c["link"] {
                items.append(FeedItem(title: title, link: link, summary: HTMLText.plain(c["summary"] ?? ""),
                                      date: c["date"].flatMap(FeedDates.parse)))
            }
            current = nil
        default:
            break
        }
    }
}

enum FeedDates {
    static func parse(_ string: String) -> Date? {
        let s = string.trimmingCharacters(in: .whitespacesAndNewlines)
        for format in ["EEE, dd MMM yyyy HH:mm:ss Z", "EEE, d MMM yyyy HH:mm:ss Z", "EEE, dd MMM yyyy HH:mm:ss zzz", "dd MMM yyyy HH:mm:ss Z"] {
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.dateFormat = format
            if let d = f.date(from: s) { return d }
        }
        let iso = ISO8601DateFormatter()
        if let d = iso.date(from: s) { return d }
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return iso.date(from: s)
    }
}

enum HTMLText {
    /// Tags stripped and entities decoded, whitespace collapsed.
    static func plain(_ html: String) -> String {
        guard html.contains("<") || html.contains("&") else { return collapse(html) }
        let text = (try? SwiftSoup.parseBodyFragment(html).text()) ?? html
        return collapse(text)
    }

    private static func collapse(_ s: String) -> String {
        s.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
}

/// The Tech news Brief's retrieval: the newest items from the user's feeds that no earlier Brief used.
enum FeedRetrieval {
    /// Items older than this aren't news.
    static let maxAge: TimeInterval = 3 * 24 * 3600

    static func fetch(_ url: String) async throws -> ParsedFeed? {
        guard let u = URL(string: url), u.scheme?.hasPrefix("http") == true else { return nil }
        var request = URLRequest(url: u, timeoutInterval: 20)
        request.setValue("Folio/0.1 (macOS reading app)", forHTTPHeaderField: "User-Agent")
        let (data, _) = try await URLSession.shared.data(for: request)
        return FeedParser.parse(data)
    }

    static func recent(from urls: [String], excluding seen: Set<String>, now: Date = .now, limit: Int = 10) async -> [RetrievedSource] {
        let feeds = await withTaskGroup(of: (String, ParsedFeed?).self) { group in
            for url in urls { group.addTask { (url, try? await fetch(url)) } }
            var out: [(String, ParsedFeed)] = []
            for await (url, feed) in group { if let feed { out.append((url, feed)) } }
            return out
        }
        return select(feeds, excluding: seen, now: now, limit: limit)
    }

    /// Newest first, unseen, recent (undated items count as recent), one link once, a few per feed at most.
    static func select(_ feeds: [(url: String, feed: ParsedFeed)], excluding seen: Set<String>, now: Date, limit: Int) -> [RetrievedSource] {
        var candidates: [(item: FeedItem, publisher: String)] = []
        for (url, feed) in feeds {
            let publisher = feed.title.isEmpty ? (URL(string: url)?.host() ?? url) : feed.title
            let fresh = feed.items.filter { item in
                !seen.contains(item.link) && (item.date.map { now.timeIntervalSince($0) < maxAge } ?? true)
            }
            candidates += fresh.prefix(4).map { ($0, publisher) }
        }
        candidates.sort { ($0.item.date ?? .distantPast) > ($1.item.date ?? .distantPast) }
        var links = Set<String>()
        let calendar = Calendar.current
        return candidates.filter { links.insert($0.item.link).inserted }.prefix(limit).map { c in
            RetrievedSource(title: c.item.title, url: c.item.link, text: String(c.item.summary.prefix(1500)), publisher: c.publisher,
                            year: c.item.date.map { String(calendar.component(.year, from: $0)) } ?? "")
        }
    }
}
