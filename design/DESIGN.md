# Folio: design spec

The design canvas is the source of truth. This folder is a snapshot of it:

- `screens/*.png`: pixel renders of every screen at 2× (1280×800 pt window). **Match these.**
- `source/*.dc.html`: the exact markup behind each render. Read it for precise numbers (sizes, paddings, colours, copy). It is HTML with inline styles; `{{holes}}` and the `<script>` block describe interactive state.
- `tokens.json`: colours, type scale, radii and spacing pulled out of the source.
- `assets/`: watercolour washes (`wc-*.png`, transparent, composite with **multiply**) and `grain.png` (a 320 px paper-grain tile).

1 CSS px in the source = 1 pt in SwiftUI.

## Principles (non-negotiable)

1. **Reader first.** When reading, the controls are hidden. Only a faint running head, a hairline progress bar and the time left are visible.
2. **Finite.** An edition is 2,200 characters or less (1–2 pages). When it's done, it's done. No feeds, infinite scroll, streaks, badges or red dots.
3. **Paper, not screen.** Use a warm paper background, ink-black text and grain everywhere. Colour comes only from the watercolour washes and one accent.
4. **Quiet AI.** AI appears only where the reader asks (Explain), or as clearly labelled content (The Brief, with its sources). It is never decoration. No sparkle icons, no gradients.
5. **Typography.** Newsreader for display, Literata for reading, Geist for the interface. No monospace anywhere. All three can be changed in Appearance.

## Window and chrome

- Use `.windowStyle(.hiddenTitleBar)` with full-size content. The traffic lights in the mockups show where the **system** buttons sit (top-left, over the sidebar). Never draw them yourself.
- Default window size 1280×800, minimum 1040×680. Content stays centred. The reader column is fixed at 620 pt and centred.
- Sidebar: 232 pt, background `#EEE7D8`, 1 pt right border `#E1D8C6`. Use a custom sidebar, not `NavigationSplitView`'s default look: the wordmark "Folio" (Newsreader italic 28), five nav rows (36 pt tall, radius 8, active fill `#E3D9C5`), and a "Next edition" card pinned to the bottom.

## Screen inventory

| # | Screen | Render | Source | Notes |
|---|---|---|---|---|
| 01 | Welcome (onboarding, step 1 of 3) | `01-welcome@2x.png` | `Onboarding.dc.html` | Left panel is 560 pt with a watercolour composition. The option cards toggle. Steps 2–3 (schedule, topics) reuse the Schedule and Library components. |
| 02 | Today | `02-today@2x.png` | `Main.dc.html` | Greeting by time of day. Two edition cards (ready / upcoming), the resurfaced highlight, and the line "Nothing else today. That's the point." |
| 03 | Reader (focus) | `03-reader@2x.png`, `03b-reader-page2@2x.png` | `Reader.dc.html` | Page turns via the edge zones (260 pt), ←/→, space and a trackpad swipe. The "Previously" recap appears on page 1 only. Small-caps opening words. "Finish this edition" on the last page. Themes: Paper, Sage, Mist, Dusk. |
| 04 | Reader with controls + Explain | `04-reader-controls-explain@2x.png` | `ReaderTools.dc.html` | Tap or move the mouse to show the top and bottom bars (72 pt, translucent `#EFE8DA`). Selecting text shows a marker highlight and the Explain popover (Explain / Define / Context / Simpler, an Ask field and Save note). |
| 05 | Edition complete | `05-edition-complete@2x.png` | `End.dc.html` | Reflection question (AI), optional reflection text, the rating (too easy / just right / a stretch), what's next, and "Close for now". |
| 06 | The Brief | `06-brief@2x.png`, `06b-brief-page2@2x.png` | `Brief.dc.html` | An AI article: kicker, title, standfirst and body. The last page lists the sources plus "Go deeper tomorrow" / "More like this" / "Less like this". |
| 07 | Library & topics | `07-library@2x.png` | `Library.dc.html` | Serial tiles with a wash cover and progress. Sources list with toggles. Topic chips. "Surprise me". "Add a book or feed" opens a file picker (EPUB/PDF) or a feed URL. |
| 08 | Notebook & recall | `08-notebook@2x.png` | `Notebook.dc.html` | Filter tabs. Highlights, notes and reflections. A "Resurfacing today" card (spaced repetition). "Ask your notebook". |
| 09 | Schedule | `09-schedule@2x.png` | `Schedule.dc.html` | Once / Twice / Custom. Delivery rows (time, content type, days). Length slider 800–2,200. "Never pile up". "Quiet arrival". A "Your day" timeline. |
| 10 | Appearance | `10-appearance@2x.png` | `Appearance.dc.html` | Paper theme, heading, reading and interface fonts, accent, and text size, with a live preview. This drives the global `Theme`. |
| 11 | Menu bar extra | `11-menubar@2x.png` | `MenuBar.dc.html` | 360×460 `MenuBarExtra(.window)`. The ready edition, the next one, pause for today, Open Folio, Settings… ⌘, |
| — | Sidebar component | `component-sidebar@2x.png` | `Sidebar.dc.html` | Shared by 02, 07, 08, 09, 10. |

## Navigation map (clickable prototype)

Welcome → Today. From Today: "Begin reading" → Reader, "peek" → Brief. Reader → controls ↔ Reader. The last page → Edition complete → Today / Brief / Notebook. The sidebar goes to Today, Library, Notebook, Schedule and Appearance, and its "Next edition" card goes to the Brief. Menu bar → Reader / Today / Schedule.

## Components to build once

`FolioSidebar`, `EditionCard`, `WashCover` (layered watercolour PNGs + grain), `PaperBackground` (colour + grain), `Kicker`, `PrimaryButton` (ink fill, radius 10, 44 pt), `SecondaryButton` (1 pt `#D6CCB8` border), `Chip` (pill; selected = ink fill), `SegmentedTabs` (sunken `#EEE7D8` track, raised selected tab), `SettingRow` (54 pt, title + meta + trailing control), `QuoteCard`, `ExplainPopover`, `PagedReader`, `ProgressHairline` (140×2).

## Accessibility

Hit targets are at least 44 pt. Body text contrast is at least 4.5:1: ink3 `#6E685E` is the lightest text allowed on paper. Honour Reduce Motion (page turns cross-fade instead of sliding) and Increase Contrast (use ink2 wherever ink3 appears). Every icon-only button has a label. Full keyboard support in the reader.
