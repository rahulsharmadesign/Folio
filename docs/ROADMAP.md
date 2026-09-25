# Roadmap: build order for Claude Code

Work one milestone at a time. Each ends with the app building and running, the listed checks passing, and a commit. Paste the **Prompt** line into Claude Code to start a milestone.

---

## M0 · Skeleton and design system
**Prompt:** `Do milestone M0 from docs/ROADMAP.md.`

- XcodeGen `project.yml` (macOS 15+, sandbox + hardened runtime entitlements from SPEC), SPM packages, bundled fonts, washes and grain in Assets.
- `Theme.swift` generated from `design/tokens.json` (4 themes, accents, type scale). `Fonts.swift` registers and resolves the heading, reading and interface families.
- Components from DESIGN.md › "Components to build once".
- App shell: hidden title bar, custom sidebar, empty screens for every route, a `MenuBarExtra` stub.

**Done when:** it builds with `xcodegen && xcodebuild`. The sidebar and an empty Today screen match `design/screens/component-sidebar@2x.png` and the frame of `02-today@2x.png`.

## M1 · Reader with local files (no AI)
**Prompt:** `Do milestone M1 from docs/ROADMAP.md.`

- EPUB and PDF importers, the Chunker with unit tests, the Library screen (07), Open With / drag-and-drop / ⌘O.
- The paged Reader (03) with keyboard, swipe and edge-zone page turns, and the controls overlay (04) without the Explain popover.
- Today (02) shows the next part as the morning edition. Edition complete (05) without AI.

**Done when:** you can open a real EPUB and a real PDF from Finder, read them in parts of 2,200 characters or less that never break mid-sentence, and the screens match 02, 03, 03b, 04 and 07.

## M2 · Schedule, delivery, menu bar
**Prompt:** `Do milestone M2 from docs/ROADMAP.md.`

- Schedule screen (09) with Once / Twice / Custom, the length slider, the "never pile up" and "quiet arrival" rules.
- `EditionScheduler`, notifications, a login item, and the menu bar extra (11).
- Onboarding (01) on first launch.

**Done when:** with a slot set 2 minutes ahead, an edition becomes ready, the menu bar shows it, and a missed edition is replaced rather than stacked.

## M3 · AI providers and reader AI
**Prompt:** `Do milestone M3 from docs/ROADMAP.md.`

- The `AIProvider` protocol, providers (Apple on-device, Ollama, OpenAI-compatible, Anthropic), the Settings › AI pane, Keychain.
- The Explain popover (04): Explain / Define / Context / Simpler / Ask, streamed. Save note → Highlight.
- The "Previously" recap and the reflection question (05).

**Done when:** each works with Ollama running locally and with one cloud key, and the app degrades cleanly when AI is off.

## M4 · The Brief
**Prompt:** `Do milestone M4 from docs/ROADMAP.md.`

- Topics in the Library (07), the Brief pipeline with Wikipedia retrieval, the Brief reader (06, 06b) with sources, "Go deeper tomorrow" and More/Less like this.

**Done when:** a Brief of 2,200 characters or less is generated for a topic you type in, lists only sources it actually retrieved, and matches 06 and 06b.

## M5 · Notebook, recall, appearance
**Prompt:** `Do milestone M5 from docs/ROADMAP.md.`

- Notebook (08) with filters, "Resurfacing today" (spaced repetition: 4 d → 2 w → 1 m → 3 m) and "Ask your notebook".
- Appearance (10) with a live preview, applied app-wide. Adaptive picks from ratings.

**Done when:** it matches 08 and 10, and changing fonts and theme updates the reader live.

## M6 · Polish and release
- Accessibility pass (VoiceOver, Reduce Motion, Increase Contrast), performance on a 1,000-page PDF, crash-free import of malformed EPUBs.
- Signing, notarization, DMG, and a README for users.
