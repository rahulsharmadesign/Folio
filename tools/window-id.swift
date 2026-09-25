#!/usr/bin/env swift
// Prints the CGWindowID of an app's largest on-screen window.
// Usage: swift tools/window-id.swift [OwnerName]   (default: Folio)
import CoreGraphics
import Foundation

let owner = CommandLine.arguments.dropFirst().first ?? "Folio"
let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
let windows = info.filter { ($0[kCGWindowOwnerName as String] as? String) == owner && ($0[kCGWindowLayer as String] as? Int) == 0 }
let best = windows.max { a, b in
    let ra = a[kCGWindowBounds as String] as? [String: CGFloat] ?? [:]
    let rb = b[kCGWindowBounds as String] as? [String: CGFloat] ?? [:]
    return (ra["Width"] ?? 0) * (ra["Height"] ?? 0) < (rb["Width"] ?? 0) * (rb["Height"] ?? 0)
}
guard let id = best?[kCGWindowNumber as String] as? Int else {
    FileHandle.standardError.write("No on-screen window for \(owner)\n".data(using: .utf8)!)
    exit(1)
}
print(id)
