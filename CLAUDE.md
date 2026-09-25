# Folio: instructions for Claude Code

Folio is a native macOS reading app: short, scheduled editions (2,200 characters or less) from the user's own EPUB/PDF books and AI-written, sourced Briefs, in a calm e-ink/paper design. Read these before any work:

1. `docs/SPEC.md`: product, architecture, data model, AI layer.
2. `design/DESIGN.md`: design principles, screen inventory, components.
3. `docs/ROADMAP.md`: build order. Work one milestone at a time, and only the one asked for.

## The design is the contract

- `design/screens/*.png` are the approved screens (2× renders of a 1280×800 pt window). **Build them exactly**: layout, spacing, type sizes, colours and copy.
- For exact values, read the matching `design/source/*.dc.html` (inline CSS; 1 px = 1 pt) and `design/tokens.json`. Never guess a value that the source states.
- Don't redesign, "improve" or add UI that isn't in the screens. If something needed isn't designed (an error state, an empty state), keep it minimal in the same visual language and list it in your summary so the designer can review it.
- The traffic lights in the mockups are the real system buttons (hidden title bar). Never draw them.
- No monospace fonts, emoji, gradients or sparkle "AI" icons. Use SF Symbols only where they match the thin 1.5 pt stroke icons in the source. Otherwise draw the SVG paths from the source as SwiftUI `Path`s.

## Visual check after every UI change

1. Build and run the app at 1280×800.
2. Screenshot the window: `screencapture -x -o -l <windowID> /tmp/folio-<screen>.png`. Get the window ID with a short Swift or AppleScript helper, which you can add under `tools/`.
3. Compare it side by side with `design/screens/<screen>@2x.png`, and fix the differences before calling the task done.

## Engineering rules

- Swift 6 strict concurrency, SwiftUI first, AppKit only for the paged text view and window chrome.
- XcodeGen: edit `project.yml`, never the `.xcodeproj`.
- The app must work fully with AI switched off. AI goes through the `AIProvider` protocol; never call a vendor SDK from a view.
- Secrets live in the Keychain only. Never log user text or keys.
- Sandbox-safe file access (security-scoped bookmarks). Never read outside what the user picked.
- The Chunker, importers and scheduler have unit tests. Run the tests before each commit.
- Commit at the end of each milestone with a clear message.

## Keeping the design in sync

The designer edits the design on a separate canvas, and refreshed exports replace the files in `design/`. When `design/` changes, diff the PNGs and sources against what's built and update only the affected views.
