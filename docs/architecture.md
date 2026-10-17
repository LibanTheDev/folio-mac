# Architecture

Folio is a native SwiftUI app for macOS 14+, built with Swift Package Manager and no third-party dependencies.

```
Sources/Folio
├── App/            App entry point, app state & navigation, sidebar, window chrome, drag types, file panels
├── DesignSystem/   Semantic tokens (colour, type, spacing, motion) and glass primitives
├── Model/          Library store, schema & migrations, books, notes, shelves, sessions, filters,
│                   analytics, insights, search, knowledge graph, exporters
├── Services/       Open Library, Goodreads CSV, on-device embeddings, reminders,
│   ├── AI/         Provider-agnostic AI (Anthropic, OpenAI-compatible), discovery, Ask Folio
│   ├── AppleBooks/ Snapshot reader, merge rules, background sync
│   └── Ebooks/     EPUB catalog providers, download manager, EPUB validation
└── Features/       Home, Library, Book, Knowledge, Ask, Discover, Stats, Search, Palette, Sessions, Settings
```

## Data

- **One JSON document** at `~/Library/Application Support/Folio/library.json`. It is versioned (schema v2), decodes tolerantly field by field, and is written atomically with a 400 ms debounce. A copy is saved before every migration and every restore, and one daily backup is kept for 14 days. An unreadable file is moved aside and never overwritten.
- **Regenerable caches** live in `~/Library/Caches/Folio/` (cover images, embeddings, Apple Books snapshots) and are never exported.
- **Downloaded EPUBs** are stored in `Folio/Ebooks/`, with a content-hash index.

## Principles

- **Local first.** Library, notes, search (including semantic search with Apple's on-device NaturalLanguage embeddings), analytics and the knowledge map work offline.
- **No invented data.** Imports never create reading activity. Progress shows where it came from. Forecasts are labelled rough when data is thin.
- **Grounded AI.** AI is optional, and the model's output is validated before it is shown. Book suggestions must exist on Open Library. Ask Folio citations and quotations must match your notes.
- **Read-only integrations.** Apple Books data is read from private snapshot copies.

## Testing

`swift test` runs 85 Swift Testing tests: persistence and migrations, merge rules, analytics, search, AI parsing and validation, Apple Books (synthetic stores), EPUB providers (captured real responses), the download manager, and exports. Opt-in live suites check real services (`FOLIO_NETWORK_TESTS`, `FOLIO_ANTHROPIC_KEY`, `FOLIO_APPLE_BOOKS_LIVE`). See [development.md](development.md).
