import Foundation
import SwiftSoup
import ZIPFoundation

/// What an importer hands to the library.
struct ImportedBook: Sendable {
    var title: String
    var author: String
    var chapters: [SourceChapter]
}

enum ImportError: LocalizedError, Equatable {
    case protected
    case unreadable
    case noText
    case unsupported

    var errorDescription: String? {
        switch self {
        case .protected: "This book is protected (DRM), so Folio can’t open it. Books you own without DRM, and public-domain EPUBs, work."
        case .unreadable: "Folio couldn’t read this file. It may be damaged."
        case .noText: "This file has no text Folio can read. Scanned PDFs aren’t supported yet."
        case .unsupported: "Folio opens EPUB and PDF files."
        }
    }
}

/// EPUB → chapters: container.xml → OPF → spine order → each XHTML → paragraphs (SPEC › Import).
enum EPUBImporter {
    static func read(_ url: URL) throws -> ImportedBook {
        let archive: Archive
        do { archive = try Archive(url: url, accessMode: .read) } catch { throw ImportError.unreadable }

        func data(_ path: String) -> Data? {
            guard let entry = archive[path] else { return nil }
            var out = Data()
            _ = try? archive.extract(entry, skipCRC32: true) { out.append($0) }
            return out
        }
        func string(_ path: String) -> String? {
            data(path).flatMap { String(data: $0, encoding: .utf8) ?? String(data: $0, encoding: .isoLatin1) }
        }

        if let encryption = string("META-INF/encryption.xml"), isDRM(encryption) { throw ImportError.protected }

        guard let container = string("META-INF/container.xml"),
              let containerDoc = try? SwiftSoup.parse(container, "", Parser.xmlParser()),
              let opfPath = try? containerDoc.select("rootfile").first()?.attr("full-path"), !opfPath.isEmpty,
              let opf = string(opfPath),
              let opfDoc = try? SwiftSoup.parse(opf, "", Parser.xmlParser())
        else { throw ImportError.unreadable }

        let base = (opfPath as NSString).deletingLastPathComponent
        let title = firstText(opfDoc, ["dc|title", "title"]) ?? url.deletingPathExtension().lastPathComponent
        let author = firstText(opfDoc, ["dc|creator", "creator"]) ?? ""

        var manifest: [String: (href: String, type: String, properties: String)] = [:]
        for item in (try? opfDoc.select("manifest > item").array()) ?? [] {
            let id = (try? item.attr("id")) ?? ""
            manifest[id] = ((try? item.attr("href")) ?? "", (try? item.attr("media-type")) ?? "", (try? item.attr("properties")) ?? "")
        }

        var chapters: [SourceChapter] = []
        for itemref in (try? opfDoc.select("spine > itemref").array()) ?? [] {
            guard let idref = try? itemref.attr("idref"), let item = manifest[idref],
                  item.type.contains("html"), !item.properties.contains("nav") else { continue }
            let path = resolve(item.href, base: base)
            guard let html = string(path) else { continue }
            chapters += self.chapters(fromXHTML: html)
        }
        chapters = mergeTiny(chapters)
        guard chapters.contains(where: { !$0.paragraphs.isEmpty }) else { throw ImportError.noText }
        return ImportedBook(title: title, author: author, chapters: chapters)
    }

    /// Font obfuscation also lives in encryption.xml; only encrypted content documents mean DRM.
    static func isDRM(_ encryptionXML: String) -> Bool {
        guard let doc = try? SwiftSoup.parse(encryptionXML, "", Parser.xmlParser()),
              let refs = try? doc.select("CipherReference, enc|CipherReference").array() else { return true }
        if refs.isEmpty { return false }
        return refs.contains { ref in
            let uri = ((try? ref.attr("URI")) ?? "").lowercased()
            return !(uri.hasSuffix(".otf") || uri.hasSuffix(".ttf") || uri.hasSuffix(".woff") || uri.hasSuffix(".woff2"))
        }
    }

    private static let blockTags: Set<String> = ["h1", "h2", "h3", "h4", "h5", "h6", "p", "li", "blockquote", "pre", "div", "dd", "dt", "td", "section", "article"]
    private static let headingTags: Set<String> = ["h1", "h2", "h3"]

    /// One XHTML document → chapters. h1–h3 start a chapter; leaf block elements are paragraphs.
    static func chapters(fromXHTML html: String) -> [SourceChapter] {
        guard let doc = try? SwiftSoup.parse(html), let body = doc.body() else { return [] }
        // Navigation, scripts and Project Gutenberg's licence boilerplate aren't reading matter.
        for selector in ["nav", "script", "style", "[id^=pg-header]", "[id^=pg-footer]", ".pg-boilerplate", "[epub|type=toc]", "#toc"] {
            try? body.select(selector).remove()
        }

        if isTableOfContents(body) { return [] }

        var chapters: [SourceChapter] = []
        var current = SourceChapter(title: "", paragraphs: [])
        let blocks = (try? body.select(blockTags.joined(separator: ",")).array()) ?? []
        for element in blocks {
            let tag = element.tagName().lowercased()
            // Only leaf blocks: a div of paragraphs is represented by its paragraphs.
            if element.children().array().contains(where: { blockTags.contains($0.tagName().lowercased()) }) { continue }
            let text = ((try? element.text()) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }
            if headingTags.contains(tag) {
                // Stacked headings ("Part One" / "Chapter 1") keep the last, most specific one.
                if !current.paragraphs.isEmpty { chapters.append(current) }
                current = SourceChapter(title: text, paragraphs: [])
            } else {
                current.paragraphs.append(text)
            }
        }
        if !current.paragraphs.isEmpty { chapters.append(current) }
        return chapters
    }

    /// A contents page that isn't marked as navigation: a "Contents" heading, or text that is mostly links.
    static func isTableOfContents(_ body: Element) -> Bool {
        let headings = ((try? body.select("h1,h2,h3").array()) ?? []).compactMap { try? $0.text().lowercased() }
        if headings.contains(where: { $0 == "contents" || $0 == "table of contents" }) { return true }
        let all = ((try? body.text()) ?? "").count
        let linked = ((try? body.select("a[href]").array()) ?? []).reduce(0) { $0 + ((try? $1.text()) ?? "").count }
        return all > 0 && linked > 40 && Double(linked) / Double(all) > 0.6
    }

    /// Epigraphs and title pages (under 300 characters) join the chapter after them.
    static func mergeTiny(_ chapters: [SourceChapter]) -> [SourceChapter] {
        var result: [SourceChapter] = []
        var carry: [String] = []
        for var chapter in chapters {
            let size = chapter.paragraphs.reduce(0) { $0 + $1.count }
            if size < 300 {
                carry += chapter.paragraphs
                continue
            }
            chapter.paragraphs = carry + chapter.paragraphs
            carry = []
            result.append(chapter)
        }
        if !carry.isEmpty {
            if result.isEmpty { result.append(SourceChapter(title: "", paragraphs: carry)) } else { result[result.count - 1].paragraphs += carry }
        }
        return result
    }

    private static func firstText(_ doc: Document, _ selectors: [String]) -> String? {
        for s in selectors {
            if let t = try? doc.select(s).first()?.text(), !t.isEmpty { return t }
        }
        return nil
    }

    private static func resolve(_ href: String, base: String) -> String {
        let clean = (href.removingPercentEncoding ?? href).components(separatedBy: "#")[0]
        guard !base.isEmpty else { return clean }
        var parts = base.components(separatedBy: "/")
        for piece in clean.components(separatedBy: "/") {
            if piece == ".." { _ = parts.popLast() } else if piece != "." { parts.append(piece) }
        }
        return parts.joined(separator: "/")
    }
}
