#!/usr/bin/env swift
// Writes FolioTests/Fixtures/sample.pdf: three pages with a running header, page numbers,
// and a word hyphenated across a line break — the cases the PDF normaliser must handle.
import AppKit

let url = URL(fileURLWithPath: "FolioTests/Fixtures/sample.pdf")
var box = CGRect(x: 0, y: 0, width: 400, height: 500)
let ctx = CGContext(url as CFURL, mediaBox: &box, [kCGPDFContextTitle as String: "PDF Fixture", kCGPDFContextAuthor as String: "A. Tester"] as CFDictionary)!
let font = NSFont(name: "Helvetica", size: 11)!
let pages: [[String]] = [
    ["The morning was quiet and the river ran slow", "under the bridge, where nobody had walked for", "a long time. It was, in every sense, an exam-", "ple of a place forgotten.", "", "A second paragraph starts on the first page and", "continues onto the next page without a break"],
    ["in the middle of its sentence, as paragraphs", "often do in printed books.", "", "A third paragraph, short and complete."],
    ["The last page has one paragraph of its own,", "which ends the document."],
]
for (i, lines) in pages.enumerated() {
    ctx.beginPDFPage(nil)
    let gc = NSGraphicsContext(cgContext: ctx, flipped: false)
    NSGraphicsContext.current = gc
    let attrs: [NSAttributedString.Key: Any] = [.font: font]
    ("A FIXTURE BOOK" as NSString).draw(at: CGPoint(x: 40, y: 460), withAttributes: attrs)
    var y: CGFloat = 420
    for line in lines {
        (line as NSString).draw(at: CGPoint(x: 40, y: y), withAttributes: attrs)
        y -= 16
    }
    ("\(i + 1)" as NSString).draw(at: CGPoint(x: 195, y: 30), withAttributes: attrs)
    ctx.endPDFPage()
}
ctx.closePDF()
print("Wrote \(url.path)")
