# Folio: product and technical spec

## What it is

Folio is a native macOS reading app with two halves:

- **Books:** the user's own EPUB/PDF files, read freely from start to finish. Folio remembers where they stopped, reopens there with a one-line "Previously" recap, and shows how much is read. Books are never rationed by the schedule.
- **Editions:** short, AI-written, **sourced** Briefs delivered on a schedule (twice a day by default, or at custom times). Each is **2,200 characters or less** (about 1–2 pages, 4 minutes). Each delivery is one kind of Brief:
  - **A true story:** a motivating story of a real person or moment, from Wikipedia.
  - **A quote, explained:** one of the user's favourite quotes (or a well-known one when their list is used up): who said it, in what context, and what it means. From Wikiquote and Wikipedia.
  - **Tech news:** a digest of the most significant recent stories from the user's news feeds (RSS/Atom), each linked.
  - **Your topics:** a topic the user chose, in their own words, from Wikipedia.
  - **A mix:** a different kind each day.

It runs locally first. It must be ready to go public later, so it's sandboxed and notarizable from day one.

## Stack

- Swift 6, SwiftUI; AppKit only where SwiftUI falls short (the paged text view, window tweaks).
- macOS 15+ deployment target. On-device Apple Intelligence features are gated with `if #available(macOS 26, *)`.
- XcodeGen (`project.yml`). The generated `.xcodeproj` is git-ignored.
- SwiftData for persistence.
- SPM packages: `ZIPFoundation` (EPUB unzip), `SwiftSoup` (XHTML → text). Add `FeedKit` later for RSS.
- Fonts are bundled from `Resources/Fonts` (all SIL OFL) and registered with `ATSApplicationFontsPath` in Info.plist.

## Architecture

```
Folio/
  App/            FolioApp.swift (WindowGroup, MenuBarExtra, Settings), AppState
  Design/         Theme.swift (from design/tokens.json), Fonts.swift, components (see DESIGN.md)
  Features/
    Onboarding/ Today/ Reader/ Brief/ EditionEnd/ Library/ Notebook/ Schedule/ Appearance/ MenuBar/
  Domain/         Models (SwiftData), Chunker, EditionScheduler, Recall (spaced repetition)
  Import/         EPUBImporter, PDFImporter, CatalogClient (Gutendex), later FeedImporter
  AI/             AIProvider protocol, providers, prompts, BriefPipeline, Retrieval (Wikipedia)
  Support/        Keychain, Notifications, Logging
Resources/        Fonts, Assets.xcassets (washes, grain)
```

### Data model (SwiftData)

- `Work`: title, author, kind (book/publication), source (upload/gutenberg/feed), fileBookmark, coverWash, status (active/paused/finished), nextPartIndex (the reading position: the part to resume at), lastReadAt.
- `Part`: work, index, text (≤ limit), chapterTitle, recap (AI, cached), charCount.
- `Topic`: label (the user's own words), isActive, pastAngles [String].
- `Brief`: kind (story/quote/news/topic), topic label, subject (the quote or angle), title, standfirst, body, sources [{title, url, publisher, year}], createdAt.
- `FavoriteQuote`: text, author?, explainedAt?, unsourced. `NewsFeed`: url, title.
- `Edition`: slotID, scheduledFor, brief, state (prepared/ready/read/replaced), rating?. (Older stores may hold passage editions; they're retired on launch.)
- `Highlight`: text, work/brief ref, range, note?, createdAt, recall {interval, ease, nextReviewAt, kept}.
- `Reflection`: edition, prompt, answer?.
- `ScheduleSlot`: time, content (mix/story/quote/news/topic), weekdays. `Preferences`: theme, fonts, accent, textSize, editionLimit, quietArrival, neverPileUp, AI provider settings (no secrets).

### Chunker (Domain/Chunker.swift)

1. Normalise the text: unwrap hard line breaks, fix PDF hyphenation (`exam-\nple` → `example`), drop running headers and footers (lines repeated on most pages).
2. Split into paragraphs. Build a part greedily until adding the next paragraph would pass `limit` (default 2,200, user range 800–2,200).
3. If one paragraph is longer than `limit`, split it at sentence boundaries (`NLTokenizer(.sentence)`).
4. Never cross a chapter boundary. The last part of a chapter may be short.
5. Recap: generated lazily by AI from the *previous* part, 140 characters or less, cached on `Part.recap`. With AI off, show "Part n of N" only.

It must be deterministic and unit-tested (a fixtures folder with a PDF, an EPUB and plain text).

### Scheduling and delivery

- `EditionScheduler` prepares the next edition up to 1 hour ahead: it uses an unread Brief of the slot's kind, or runs the Brief pipeline for that kind. "A mix" rotates story → quote → news → topic by day.
- With AI off there are no editions; Today says so and points to Settings › AI. Books work fully.
- `UNCalendarNotificationTrigger` for each slot. With "Quiet arrival" on, there's no banner: only the menu bar extra shows a dot.
- **Never pile up:** when a new edition becomes ready, any unread one from an earlier slot becomes `replaced`.
- Keep the menu bar extra alive with a login item (`SMAppService.mainApp`) so editions arrive when the window is closed.

### Reader

- Books read continuously: the reader lays out a window of consecutive parts from one chapter (at most 16 parts), and paging past either end moves to the next or previous window. Each page turn saves the position (`Work.nextPartIndex`, `lastReadAt`). Reopening a book starts at that part, with "Previously" on top.
- Paged, not scrolling. Use TextKit's classic pagination: one `NSLayoutManager` with a sequence of fixed `NSTextContainer`s (620 pt wide, height = available space), each shown in a non-editable, selectable `NSTextView` hosted in SwiftUI (`NSViewRepresentable`).
- Input: ←/→/space, a two-finger swipe, or a click in the 260 pt edge zones. Esc returns to Library (books) or Today (Briefs).
- Moving the mouse or pressing ⌘/ shows the chrome, which fades out after 2.5 s idle.
- Selection opens the Explain popover (see AI). Highlight uses the marker style from tokens.
- Text size, fonts and theme update live from `Theme`.

### Import (local files)

- File › Open (⌘O), drag-and-drop onto the window or the Dock icon, "Open With › Folio" in Finder, and Library › "Add a book or feed".
- Declare document types for `org.idpf.epub-container` and `com.adobe.pdf` (viewer role). Handle them in `application(_:open:)` or `.onOpenURL`.
- Copy the imported file into `~/Library/Containers/…/Application Support/Folio/Library/` (or keep a security-scoped bookmark) so it works under the sandbox.
- **EPUB:** unzip → `META-INF/container.xml` → OPF → spine order → each XHTML → text via SwiftSoup (keep paragraph breaks, headings become chapter titles; skip nav/toc). Title and author come from OPF metadata.
- **PDF:** `PDFKit` → `page.string` per page → normaliser. Scanned PDFs (no text layer) come later, via Vision `VNRecognizeTextRequest`.
- DRM-protected files: detect them (`META-INF/encryption.xml`) and show a polite "can't open protected books" message.
- Public domain: Project Gutenberg through the Gutendex JSON API. Standard Ebooks: import downloaded EPUBs (check their current feed and access terms before automating).

## AI layer

The AI is pluggable, local-first and optional. Books work fully with AI turned off. Editions are Briefs, so with AI off there are no editions, recaps or Explain; Today says so plainly.

```swift
protocol AIProvider {
  var id: String { get }
  var isAvailable: Bool { get async }
  func complete(_ req: AIRequest) async throws -> String
  func stream(_ req: AIRequest) -> AsyncThrowingStream<String, Error>
}
```

Providers, chosen in Settings › AI:

1. **Apple on-device** (`FoundationModels`, macOS 26+, Apple silicon with Apple Intelligence on): private, free, offline. The default when available. Good for Explain, Define, recaps and reflection questions.
2. **Ollama** (local): `http://localhost:11434`. List models from `/api/tags` and use its chat API.
3. **OpenAI-compatible**: base URL + key + model. This covers LM Studio (`localhost:1234/v1`), Groq, OpenRouter, OpenAI and others.
4. **Anthropic**: the Messages API with the user's key.

Keys live in the Keychain only. Model lists are fetched, never hard-coded. Each feature can have its own provider (e.g., Explain on-device, Brief on a larger cloud model).

### AI features and rules

| Feature | Input | Output rules |
|---|---|---|
| Explain / Define / Context / Simpler | the selection + the surrounding paragraph + the work's title and author | 60 words or less, plain prose, no lists. Context may state dates only if they are in the text or metadata. |
| Ask about this passage | question + the part's text | Answer from the passage. Say so when the answer isn't in it. |
| Recap ("Previously") | the previous part | One sentence, 140 characters or less, past tense, no spoilers beyond that part. |
| Reflection question | the part just read | One open question, 30 words or less, tied to a concrete image in the text. |
| The Brief | topic + past angles + retrieved sources | See the pipeline below. |
| Ask your notebook | highlights + reflections (local) | Cite which highlights it used. |
| Adaptive picks | ratings (too easy / just right / a stretch), More/Less like this | Adjust topic weights and which works appear. Rule-based first; AI only suggests. |

**Brief pipeline:** choose an angle (AI, avoiding past angles) → retrieve (by kind: Wikipedia search → top 2–3 article extracts for stories and topics; Wikiquote search + the speaker's Wikipedia article for quotes; the user's RSS/Atom feeds, newest unseen items, for tech news) → write, **grounded only in the retrieved text**, as title + standfirst + body of **2,200 characters or less** → validate (length, and every source it lists must be one it was given; retry once, otherwise skip) → store with sources. With no sources, there's no Brief (retry that kind after 30 minutes). For a quote Folio picks itself, the quote must appear verbatim in a retrieved Wikiquote page. Interpretation of a quote may be the model's own; every fact must come from the sources. Always label it "Written by AI from these sources".

**Privacy:** no analytics. Text goes to a cloud provider only when the user picked that provider, and Settings says so plainly.

## Going public later (keep this true from day one)

- App Sandbox on, with entitlements: `files.user-selected.read-only`, `files.bookmarks.app-scope`, `network.client`.
- Hardened Runtime on. Sign with a Developer ID, notarize (`notarytool`), staple, then ship a DMG via GitHub Releases or the Mac App Store.
- Bundled fonts are OFL: include `Resources/Fonts/licenses`.
- Content: ship only public-domain catalogues. User files stay on the device.
