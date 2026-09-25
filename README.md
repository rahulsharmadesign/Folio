# Folio

A calm macOS reading app: a page or two of something worth your attention, twice a day.

## Start building with Claude Code

```bash
cd path/to/Folio
git init && git add -A && git commit -m "Design handoff"
brew install xcodegen        # if you don't have it yet
claude                       # Claude Code reads CLAUDE.md automatically
```

Then, in Claude Code:

```
Read CLAUDE.md, docs/SPEC.md, design/DESIGN.md and docs/ROADMAP.md, then do milestone M0.
```

After each milestone, run the app, compare it with `design/screens/`, and move on with `Do milestone M1 from docs/ROADMAP.md.` and so on.

## What's in here

- `design/`: the approved screens (PNG), their exact source, tokens, and watercolour and grain assets.
- `docs/SPEC.md`: product and architecture, including local AI (Apple on-device / Ollama) or your own API key.
- `docs/ROADMAP.md`: milestones M0–M6, each with a ready prompt.
- `Resources/Fonts/`: Newsreader, Literata, Geist and the Appearance alternates (all SIL OFL, licenses included).

## Local AI

- **Ollama** (already on this Mac): `ollama serve`, then pull a small instruct model and pick it in Folio › Settings › AI.
- **Apple Intelligence** (macOS 26+): used automatically when available.
- **API key:** Anthropic, OpenAI, Groq or any OpenAI-compatible endpoint. The key is stored in the Keychain.
