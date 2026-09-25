#!/usr/bin/env swift
// Visual diff of a screenshot against its design render.
// Usage: swift tools/compare.swift design.png built.png out.png [x y w h]  (optional crop in pt)
// Writes out.png: design | built | difference (amplified ×4), and prints the mean difference.
import AppKit

let args = CommandLine.arguments
guard args.count >= 4,
      let a = NSImage(contentsOfFile: args[1])?.cgImage(forProposedRect: nil, context: nil, hints: nil),
      let b = NSImage(contentsOfFile: args[2])?.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
    print("usage: compare.swift design.png built.png out.png [x y w h]"); exit(1)
}
var crop = CGRect(x: 0, y: 0, width: a.width, height: a.height)
if args.count >= 8, let x = Double(args[4]), let y = Double(args[5]), let w = Double(args[6]), let h = Double(args[7]) {
    crop = CGRect(x: x * 2, y: y * 2, width: w * 2, height: h * 2) // pt → @2x px
}
func pixels(_ img: CGImage) -> [UInt8] {
    let w = Int(crop.width), h = Int(crop.height)
    var buf = [UInt8](repeating: 0, count: w * h * 4)
    let ctx = CGContext(data: &buf, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.draw(img, in: CGRect(x: -crop.minX, y: -(CGFloat(img.height) - crop.maxY), width: CGFloat(img.width), height: CGFloat(img.height)))
    return buf
}
let pa = pixels(a), pb = pixels(b)
let w = Int(crop.width), h = Int(crop.height)
var out = [UInt8](repeating: 255, count: w * 3 * h * 4)
var total = 0.0
for y in 0..<h {
    for x in 0..<w {
        let i = (y * w + x) * 4
        var d = 0
        for c in 0..<3 {
            let diff = abs(Int(pa[i + c]) - Int(pb[i + c]))
            d = max(d, diff)
            out[(y * w * 3 + x) * 4 + c] = pa[i + c]
            out[(y * w * 3 + w + x) * 4 + c] = pb[i + c]
        }
        total += Double(d)
        let v = UInt8(max(0, 255 - min(255, d * 4)))
        for c in 0..<3 { out[(y * w * 3 + 2 * w + x) * 4 + c] = v }
    }
}
print(String(format: "mean max-channel difference: %.2f / 255", total / Double(w * h)))
let ctx = CGContext(data: &out, width: w * 3, height: h, bitsPerComponent: 8, bytesPerRow: w * 12,
                    space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: args[3]))
