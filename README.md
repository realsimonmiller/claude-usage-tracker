# claude-usage-tracker

A macOS menu bar widget that shows how close you are to your Claude Code plan cap, with a Doom-style HUD face that gets bloodier as your remaining quota shrinks.

## Status

Pre-alpha. Scaffolding only.

## How it works

Parses local Claude Code transcripts in `~/.claude/projects/**/*.jsonl` to compute a rolling 5-hour and 7-day token window. No network calls, no scraping, no auth. The `usage` block on each assistant turn (input/output/cache tokens) is summed and weighted per model.

## Stack

- Native macOS app (Swift / SwiftUI)
- `NSStatusItem` menu bar icon + SwiftUI popover for details
- `LSUIElement = YES` (no Dock icon)
- FSEvents for incremental transcript watching

## Doom face

Five face buckets mapped to usage thresholds (0-20%, 20-50%, 50-75%, 75-95%, 95-100%), plus a dead face at cap and an evil grin on window reset. Sprites sourced from [Freedoom](https://freedoom.github.io/) (BSD-licensed) — not the original Doom WADs.

## Roadmap

See plan in `~/.claude/plans/i-want-to-create-curried-cerf.md` for the full build sequence. Short version: scaffold → JSONL parser → live FSEvents wiring → popover → settings → notarize.

## License

[MIT](./LICENSE)
