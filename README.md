# Folio

> Goodreads catalogs what you've read. Folio helps you understand what you've learned.

A private, native macOS reading library and personal knowledge system: Goodreads-style tracking, StoryGraph-style analytics, a Readwise-style knowledge vault, and an AI research assistant grounded in your own notes. It's built with SwiftUI and a frosted, native design.

## Build & run

Requires macOS 14+ and the Xcode Command Line Tools.

```bash
./build_app.sh        # builds Folio.app (release), icon included, ad-hoc signed
open Folio.app
swift test            # 60 tests (Swift Testing)
FOLIO_NETWORK_TESTS=1 swift test --filter NetworkTests   # optional live Open Library checks
```

Your data lives in `~/Library/Application Support/Folio/library.json`, with daily backups in `Backups/`. To try Folio against a throwaway library, set `FOLIO_DATA_DIR`:

```bash
open -n --env FOLIO_DATA_DIR=/tmp/folio-demo Folio.app
```

## What's inside

- **Library:** resizable cover gallery, kanban board (drag between statuses) and a sortable list. Multi-facet filters. Collections and rule-based smart shelves. Tags. Full book pages with reread history, editions, related books and finish forecasts.
- **Home:** a live dashboard with data-backed stats, reading sessions, a drag-to-reorder Up Next queue, recent knowledge and an activity heatmap.
- **Insights:** pace, consistency, streaks, monthly charts, genres and subjects, completion rate, a full-year heatmap, and finish predictions with uncertainty ranges.
- **Knowledge:** highlights, quotes, reflections, lessons, mental models and questions, with a Markdown editor, autosave, tags and note-to-note connections. Includes an interactive intellectual map.
- **Search:** keyword plus on-device semantic search (Apple NaturalLanguage) across books and notes; every result links to its source.
- **Ask Folio:** grounded answers about what you've learned. Citations and quotes are verified against your notes, and your notes, book information and general AI knowledge are clearly separated.
- **Discover:** AI recommendations, each verified against Open Library before it's shown; Open Library browsing otherwise.
- **Mac-native:** ⌘K command palette, keyboard shortcuts, drag and drop, reading reminders, light and dark appearance, Reduce Motion support and accessibility labels.
- **Your data:** Goodreads CSV import (drop the file on the window) and export, a full JSON backup and restore, Markdown notes export (Obsidian-friendly), sessions CSV, and optional daily iCloud Drive backups.

## Privacy & AI

AI is **off by default**. When you turn it on (Settings → AI), you choose the provider: Anthropic Claude, or any OpenAI-compatible server such as a local Ollama or LM Studio. Keys are stored in the macOS Keychain. Separate switches control whether library metadata and notes may be sent. Only the passages relevant to each question are sent, never your whole vault. Search, semantic matching, analytics and the knowledge map always run on your Mac.

See [FOLIO_ROADMAP.md](FOLIO_ROADMAP.md) for the architecture, milestone log, sync evaluation and known limitations.
