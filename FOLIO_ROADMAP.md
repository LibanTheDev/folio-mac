# Folio Roadmap

> Goodreads catalogs what you've read. Folio helps you understand what you've learned.

Repository: https://github.com/LibanTheDev/folio-mac (private)

## 1. Audit of the existing app (baseline `4ec0bc7`)

| Area | Finding |
|---|---|
| Stack | Swift 6.1 toolchain (Command Line Tools only, no Xcode), SwiftPM executable target, SwiftUI + AppKit, Swift Charts. macOS 14+ deployment target. No third-party dependencies. |
| App packaging | `build_app.sh` assembles `Folio.app`, generates the icon, and ad-hoc codesigns it. No Xcode project, no entitlements, no developer team. |
| Architecture | Single `Library` `ObservableObject` (store and business logic) plus an `AppState` for navigation. Views read the store through `@EnvironmentObject`. |
| Navigation | Custom sidebar, a top tab bar (Home / My Books / Discover / Stats) and a right-hand inspector. |
| Design | Warm beige "paper" palette in `Theme.swift`, plus button styles and small primitives. No materials or vibrancy. |
| Data model | `Book` (metadata, status, rating, review, tags, dates, `progressLog`, `notes`, `readCount`). `BookNote` only distinguishes quote from note. |
| Persistence | One JSON file at `~/Library/Application Support/Folio/library.json`, written atomically with a 400 ms debounce. **No schema version, no migration path, no backups.** Synthesized `Codable` fails if a non-optional field is missing, so adding fields would break old files. |
| Metadata | Open Library search, trending, work descriptions and covers. Lazy enrichment of imported books. In-memory cover cache backed by URLCache. |
| Goodreads | RFC-4180 CSV parser (quoted ISBNs, multiline reviews, custom shelves, DNF detection), de-duplicating import, and Goodreads-compatible CSV export. |
| Shelves | Four statuses (want, reading, read, DNF), favourites and free-form tags. No ordering, no smart shelves, no collections. |
| Analytics | Yearly goal, books per month, rating distribution, highlights, top authors and a streak from progress logs. No time tracking. |
| Tests | **None.** XCTest is unavailable with Command Line Tools; Swift Testing (`import Testing`) works. |
| Weaknesses | Logic and UI share one target, so they can't be unit-tested. No migrations. Rereads overwrite earlier dates. Notes aren't searchable. Single-window state only. |

## 2. Architecture decisions

- **Split into `FolioCore` (library) and `Folio` (app)** so models, persistence, analytics, search and AI orchestration are unit-testable with Swift Testing.
- **Keep JSON persistence**, made robust: a schema `version`, tolerant decoding (every new field has a default), automatic pre-migration backups, and rolling daily backups. JSON stays human-readable and exportable, and it scales to thousands of books and tens of thousands of notes (a few MB). SwiftData/CloudKit need a signed developer team and are not justified yet.
- **Rereads** are modelled as `ReadThrough` history entries, so previous reads are never overwritten.
- **Semantic search runs locally** with Apple's `NaturalLanguage` sentence embeddings (offline, private), combined with keyword scoring.
- **AI is provider-agnostic** (`AIProvider` protocol: Anthropic and any OpenAI-compatible endpoint, including local Ollama or LM Studio). It is off by default, keys are stored in the macOS Keychain, and per-category consent controls what personal data is sent.
- **Grounding:** AI answers cite numbered sources. Citations and quotes are validated against stored material before display, and anything unverifiable is flagged.

## 3. Milestones

Status legend: ✅ done · 🚧 in progress · ⏳ planned · ⛔ blocked (needs external setup)

| # | Milestone | Status | Commit |
|---|---|---|---|
| 0 | Private GitHub repo and baseline | ✅ | `4ec0bc7` |
| 1 | Audit and roadmap | ✅ | (this file) |
| 2 | Frosted macOS design system | ✅ | see log |
| 3 | Library gallery, smart shelves, book detail, rereads | ✅ | see log |
| 4 | Live home dashboard | ✅ | see log |
| 5 | Reading sessions and analytics | ✅ | see log |
| 6 | Personal knowledge vault and search | ✅ | see log |
| 7 | AI-powered discovery | ✅ | see log |
| 8 | Ask Folio and knowledge graph | ✅ | see log |
| 9 | Command palette, notifications, backups/sync, export | ✅ | see log |
| 10 | Final QA | ✅ | see log |
| 11 | Read-only Apple Books synchronization | ✅ | see log |
| 12 | Find EPUB: open-licence catalogs and download manager | ✅ | see log |
| 13 | README showcase and documentation | ✅ | see log |

## 4. Known constraints

- **iCloud / CloudKit sync** needs an Apple Developer team, the iCloud entitlement and a provisioning profile. The current ad-hoc-signed build can't use CloudKit. See §6.
- **GUI verification** is done by driving the running app through accessibility automation and screenshots. Native drag sessions can't be synthesized that way, so drag-and-drop is verified by code review and manual testing.
- **Liquid Glass APIs** (`glassEffect`) require macOS 26. This machine runs macOS 15, so the design uses `NSVisualEffectView` and SwiftUI materials, which are the native equivalent on 14–15.

## 5. Feature coverage log

Updated at each milestone below.

### Milestone 2: Frosted design system
- `DesignSystem/Tokens.swift`: semantic color tokens (cool pearl / deep charcoal, icy-blue accent, status and chart palettes), radii, spacing, type scale (system UI, New York serif only for literary headings), and `Motion` helpers that respect Reduce Motion.
- `DesignSystem/Primitives.swift`: native `NSVisualEffectView` vibrancy, window configurator (transparent titlebar, full-size content), glass levels (panel / card / control) with hairline and specular edge, hover glass, and atmosphere backdrop. Also: primary, glass, ghost, icon and pill buttons; segmented control with a sliding selection; search field; text field style; sheet container; page and section headers; chips and a flow layout; progress bar and ring; empty state; stat card; sidebar rows.
- App shell: floating frosted sidebar and inspector panels, a translucent content area, a centered glass navigation capsule, and a draggable titlebar area.
- Appearance follows the system by default (Light / Dark override in View → Appearance).
- Verified visually in light and dark mode via the running app.

### Milestone 3: Library, shelves, book pages
- **Schema v2** (`Model/`): `version` field, tolerant per-field decoding (`Codable+Defaults`), fractional-second ISO-8601 dates, pre-migration backup, daily rolling backups (14 kept), and an unreadable file is never overwritten (moved aside, saving disabled). Tested with the v1 fixture.
- **Rereads:** `ReadThrough` history. Starting a reread, or moving a finished book back to Reading, archives the previous pass with its dates and rating.
- **Typed knowledge notes:** highlight, quote, reflection, chapter note, lesson, mental model, takeaway, question. Notes carry page, chapter, tags and links. v1 quote/note values migrate automatically.
- **Collections and smart shelves:** manual ordered collections, rule-based smart shelves (13 fields, all/any matching), 7 templates, create/edit/rename/reorder (drag or menu)/delete, and drop books onto collections in the sidebar. Tags can be renamed and deleted.
- **Gallery:** resizable cover grid (slider), board, and a sortable list with publication year, completion and added-date columns. Multi-facet filter popover (status, rating, genre, author, tags, shelves, publication year, pages, date added, year completed) with removable filter chips. Shared context menu across views.
- **Book detail page:** hero with cover, genres, authors (click to filter), status, rating, sessions and re-read actions. Progress with finish forecast. About. Highlights & Notes grouped by type. Mental Models. Review. Editable details (ISBN, edition, format, publisher). Reading history. Tags and collections. Related books (library ranking plus more by the author from Open Library).
- Goodreads re-import now merges: it refreshes Goodreads-owned fields and keeps Folio-only data.
- Tests: 24 (persistence and migration, rereads, merge, queue, deletion cleanup, tags, smart-shelf rules, filters, related books, forecast, streaks, 5,000-book performance).

### Milestone 4: Live home dashboard
- Time-aware greeting ("Good afternoon.") with "A little reading every day adds up." (refreshes every minute).
- Stat cards only show what the data supports: books completed and pages read this year always; streak only once activity exists; reading time only once sessions exist. Pages read = whole pages of books finished this year plus pages logged this year on unfinished books, labelled as such.
- Live session banner and top-bar session pill, with pause/resume and finish (records end page) or discard.
- Currently Reading cards: progress, %, pages left, forecast finish date (marked rough when data is thin; "needs more data" when there is none), quick page update and one-click session start.
- Up Next queue with persistent drag-to-reorder (`queueRank`), plus Start Reading and Move to Front.
- Recent Knowledge cards from the latest saved notes. A width-adaptive GitHub-style activity heatmap. Recently Finished row.
- Imported history never creates activity. When a first progress update comes days after the start date, its pages are spread across those days without marking them as reading days.
- Tests: year stats from imports vs recorded data, session pause and resume time accounting, accidental-tap rejection, first-update spreading.

### Milestone 5: Reading analytics
- Reading sessions: start, pause, resume and finish (live timer; paused time excluded; sub-10-second empty sessions ignored), plus manual historical entry with validation. Session lists with delete on the book page and on Insights. The active session survives app restarts.
- **Insights** page (replaces Stats): books completed, pages read, pages per day, reading time, consistency (% of days with recorded reading), current and longest streaks, reading-challenge goal, completion rate (year and all time) and abandoned books. A full-year GitHub-style heatmap. Books completed and logged pages per month (separate charts, no dual axis, hover tooltips, whole-number ticks for counts). Genre donut (top 6 plus Other, legend with counts). Subject bars. Ratings distribution. Highlights. Most-read authors.
- **Finish predictions** for every in-progress book: based on the last 3 weeks of that book's recorded pace, with an earliest–latest range. Marked "rough" with few data points, and "not enough data" when there's nothing recorded.
- Chart colors use a CVD-validated categorical palette with separate light and dark steps (validated with the dataviz checker; the first palette failed the chroma check and was replaced).
- Goodreads imports never create sessions or activity (tested).

### Milestone 6: Personal knowledge vault
- **Knowledge** page (top nav and sidebar): every highlight, quote, reflection, chapter note, lesson, mental model, takeaway and question across all books. Filter by type, book and tag; search by keyword plus meaning.
- **Note editor:** a native `NSTextView` Markdown editor (undo, spellcheck) with selection-aware formatting (bold ⌘B, italic ⌘I, code, bullets, quotes, links) and an Edit/Preview toggle. Chapter, page and tags. Autosaves on every keystroke (debounced write, verified on disk). Notes render bullets, block quotes and headings.
- **Global search** (top field on Home/Insights): books (title, author, tags, description, review) and notes (text, tags, chapter), with snippets and "matched X" labels. Every result opens its source (book page or the exact note). Stop words and a 50% keyword-coverage rule keep it precise.
- **Semantic retrieval, fully on-device:** Apple `NaturalLanguage` sentence embeddings, cached on disk in Caches (regenerable, never exported). The cutoff is relative (mean + 0.8 SD with a floor), because absolute similarity from this model varies with query length (measured before tuning).
- **Cross-book connections:** manual links between notes (stored one-way, displayed with backlinks), a link picker, unlinking, and cleanup when notes or books are deleted. **Suggested connections** come from local embeddings (opt-in per suggestion, nothing uploaded).
- Tests: keyword search and snippets, stop words, links/backlinks/cleanup, timestamp-on-change, Markdown stripping, semantic retrieval with no shared keywords, cutoff selection.

### Milestone 7: AI-powered discovery
- **Provider-agnostic AI layer** (`Services/AI`): an `AIProvider` protocol with two implementations.
  - **Anthropic:** raw HTTPS (no Swift SDK exists), default `claude-opus-5-5`, structured JSON output via `output_config.format`, effort `medium`, server-side refusal fallbacks (`fallbacks: "default"`), and `refusal` / `max_tokens` stop reasons handled before reading content.
  - **OpenAI-compatible:** for local Ollama or LM Studio (fully offline) or hosted endpoints.
- **Privacy:** AI is **off by default**. Keys are stored in the **macOS Keychain**. Separate consent switches cover library metadata and notes, and the exact disclosure ("Sends … to …") is shown next to every AI action. Notes are only shared as the few passages relevant to the query (found locally).
- **Discover → For You:** describe what you want, or use the four example prompts. The model proposes; **every suggestion is verified against Open Library** (title, ignoring subtitles and articles, plus author surname). Unverifiable suggestions are hidden and counted, with an opt-in "treat with caution" list. Books already owned or dismissed are skipped. Each card shows verified title, author, year, cover, the Open Library description, the AI reason (labelled "AI-generated"), related books from your library (matched to real entries), and Want to Read / Details / Not for me (remembered and sent as "don't recommend").
- **AI-off fallback:** a natural-language keyword search on Open Library (filler words removed, widened to subject searches when results are thin).
- **Settings window** (⌘,): General (appearance, show library file, backups folder) and AI (provider, model, key, consent, interests, connection test).
- Tests: request shape, stop-reason parsing, JSON extraction, consent-gated prompts, title/author matching, verification dropping invented, owned and dismissed books, invalid model output, and a Keychain round trip. A live Open Library verification test (`FOLIO_NETWORK_TESTS=1`) passes: 4 real books verified, 1 invented title rejected. It also caught a subtitle false negative, which is now fixed.
- ⚠️ **Not verified end-to-end against a real model:** no API key and no local model server were available in the build environment. The provider code is unit-tested against the documented response shapes. Add a key in Settings → AI and use Test Connection.

### Milestone 8: Reading intelligence
- **Ask Folio** (top nav and sidebar). Six modes: Ask, Recurring Themes, Disagreements, Compare Authors, Mental Models and Topic Summary.
- **Retrieval runs on this Mac:** hybrid keyword and on-device semantic search with looser coverage for questions, plus notes from books or authors named in the question. Each source is numbered: S# for the reader's notes, M# for book information.
- **Grounded answers:** the model must answer in three clearly labelled sections: *From your notes* (each paragraph must cite an S-source), *From book information* (M-sources), and *General knowledge* (uncited, visually distinct, never attributed to the reader).
- **Validation before display:** citations that don't match a sent source are removed and flagged. Note-based paragraphs without a valid note citation are dimmed and marked unverified. Any quoted phrase must appear verbatim in a source, otherwise it is flagged. If no note-based claim survives, the answer is marked "insufficient evidence".
- Citation chips open a popover with the exact source text and a link to the note or book. Every source sent can be listed.
- **Consent:** needs AI on plus "notes" sharing, and only relevant passages are sent. Without consent (or offline), Ask Folio shows **"What your notes say"**: the retrieved passages grouped by book, computed locally.
- **Intellectual map** (Knowledge → Map): books, authors, concepts (book tags, note tags, genres; only concepts linking two or more items), notes and mental models. Note links are edges, and **every edge records its reason** ("book tagged #sci-fi", "written by…", "connected notes"). Deterministic force layout, pan and pinch-zoom, hover and select highlighting of the neighbourhood, type filters, focus on a concept or author (2-hop subgraph), and an inspector listing connections with reasons and links to the book or note.
- Tests: citation and quote validation (valid, fabricated, missing), section ordering, the prompt with and without sources, retrieval by named author and by book title and tags, graph construction (traceable edges, singleton concepts dropped), focus neighbourhood, and deterministic, normalized layout.
- ⚠️ As with milestone 7, synthesized answers were not exercised against a live model (no key or local server here). The local evidence mode and all validation logic were verified.

### Milestone 9: Premium Mac integrations
- **⌘K command palette:** search books and notes; go to pages, statuses, shelves and tags; recent books; actions (add book, new collection or smart shelf, import, export backup or Markdown, open Settings); per-book **Update Progress** (asks for a page) and **Start Reading Session**; live session pause/resume/finish. Arrow keys, Return and Escape all work. Also a ⌘ button in the top bar. Verified end to end: updating a page from the palette moved progress and the stats.
- **Drag and drop:** a typed `Transferable` (`app.folio.reader.item`, declared in Info.plist). Inside Folio it carries a book or shelf reference; dropped into other apps it becomes "Title by Author" (no internal IDs leak). Works for board columns (status), sidebar collections (add), shelf reordering, and the Up Next queue. **Drop a Goodreads CSV anywhere on the window** to import it.
- **Reading reminders** (Settings → Reminders): local notifications on chosen weekdays and time, mentioning current books and streak. Permission is requested only when the user turns them on.
- **Data ownership:** File → Export → complete Folio backup (JSON), notes as Markdown (one file per book with YAML front matter, notes grouped by type, `[[links]]` for connections, plus an index; works with Obsidian), Goodreads CSV, and reading sessions CSV. File → Restore from Folio Backup shows what's inside and saves the current library to Backups first.
- **Offline-first:** library, tracking, notes, search (including semantic), analytics, map and the evidence view need no network. Open Library and AI calls degrade to clear messages, and covers fall back to generated placeholders.
- Keyboard: ⌘1–6 pages, ⌘K palette, ⌘F search, ⌘N add book, ⇧⌘N collection, ⌥⌘N smart shelf, ⌥⌘I inspector, ⌘[ back from a book page, ⌘B/⌘I in the note editor, ⌘↩ submit in Discover and Ask.
- Tests: Markdown export, sessions CSV escaping, iCloud backup daily write and pruning, reminder triggers and copy, drag payload, and restore safety backup.

### Milestone 10: Quality assurance
| Check | Result |
|---|---|
| Release build (`swift build -c release`, `build_app.sh`) | ✅ 0 errors, **0 warnings** |
| Type checking / lint | ✅ The Swift 6.1 compiler is the type checker. `swift format lint` (config in `.swift-format`) reports only whitespace/layout differences and no semantic findings. A mass reformat was intentionally not applied to keep history readable. |
| Tests | ✅ **63 passing** (Swift Testing), plus opt-in live suites: Open Library verification and Claude end-to-end, both passing |
| Persistence & migrations | ✅ v1 → v2 migration with pre-migration backup (tested and seen in the app). Tolerant decoding. An unreadable file is never overwritten. Fractional-second dates round-trip. Restore makes a safety backup. |
| Goodreads data integrity | ✅ CSV → merge → save → reload test checks every imported field. Re-import keeps Folio-only data. Imports never create sessions or activity. |
| Navigation | ✅ Every page, the detail page, the inspector, sheets, the palette and Settings were driven in the running app |
| Light & dark | ✅ Both checked visually (gallery, board, list, home, insights, knowledge, map, settings) |
| Accessibility & contrast | ✅ Text tokens re-stepped after measuring: all text colours and the accent/status colours used as text are now **≥ 4.5:1** on canvas and cards in both appearances (tertiary light was 2.7:1, accent 4.0:1). The primary button gradient now keeps white text ≥ 4.5:1. Charts use a CVD-validated palette. Reduce Motion is respected. Accessibility labels are on icon-only controls, the heatmap, the map and the palette. |
| UI glitches found & fixed during QA | Fractional count axes; uneven stat tiles; narrow heatmap; random default note type; map tap not registering; search matching filler words; first progress update over-crediting one day; subtitle false negatives in verification; pasted page numbers with newlines; "other 1 books" copy |
| Placeholder buttons | ✅ None. Every button performs a real action (scanned for empty actions and TODOs). |
| Secrets & private data | ✅ The staged tree was scanned for keys and tokens; `.gitignore` excludes `.env`, keys, `library.json`, SQLite and build output. The test fixture contains only synthetic demo data. |

**Known limitations**
- ~~AI features not run against a live model~~ **Verified live against `claude-opus-5-5`** (opt-in `LiveAITests`, key read from `FOLIO_ANTHROPIC_KEY`, never stored): structured connection check; discovery returned 8/8 suggestions verified on Open Library after fixing lookup fallbacks (author initials and leading articles had caused 2 real books to be rejected); Ask Folio produced note-cited paragraphs with zero invalid citations or unverified quotes. The OpenAI-compatible provider remains untested against a live server.
- Native drag sessions can't be synthesized by the automation used for GUI checks. Drop handling is code-reviewed and uses standard SwiftUI `Transferable` APIs; please verify by hand.
- Live multi-device sync needs Apple Developer signing (see §6). Daily iCloud Drive backups are available now.
- Notifications need the user's permission the first time reminders are enabled. They were not triggered during QA, to avoid prompting on this Mac.

### Milestone 11: Apple Books synchronization (read-only)
Full details are in [docs/apple-books-sync.md](docs/apple-books-sync.md).
- **Verified on real data** (Apple Books 7.6, build 6387, macOS 15.7), merged into a throwaway library: 96 books imported; 34 confirmed progress values; 1 finished book with its real date; 8 highlights imported (7 with chapter titles); 7 highlights skipped because their books are no longer in Apple Books; the second sync was idempotent. Checksums show Apple's files unchanged during the read.
- Reads **snapshot copies** of `BKLibrary` and `AEAnnotation` (database plus WAL and SHM files), with schema validation and per-field fallbacks. A missing or changed store is reported and nothing is modified.
- Forward-only merge: dedupe by asset ID, then title and author; fill only missing metadata; never change ratings, reviews, collections or user notes; never move status backwards; never invent start dates or sessions.
- Highlights carry source attribution. Edited or tagged imports are never overwritten or removed.
- Event-driven sync (watchers on Apple's folders and WAL files, 3-second debounce, about 4 seconds end to end in testing), plus a 5-minute timer and a sync on app activation. Sync starts at launch.
- Connected Libraries tab in Settings, an Apple Books shelf, and progress provenance labels ("Confirmed by Apple Books", "Logged in Folio", "Progress unknown").
- Bugs found and fixed while verifying: the sync didn't start when the window was restored minimized; a checkpointed WAL store with no `-shm` file was misreported as an unsupported schema.

### Milestone 12: Find EPUB
- A **Find EPUB** action inside the existing Discover book modal (no separate screen). A provider-agnostic `EbookProvider` interface with **Standard Ebooks** (public Atom feed) and **Project Gutenberg** (official OPDS catalog). Only works the provider marks as public domain are listed, and its licence text is shown verbatim.
- Searches by title and author, and by ISBN (resolved through Open Library). Shows format, language and exact file size. Neither catalog states the original publication year, so none is shown.
- Download manager: progress, up to 3 retries with backoff for transient failures only, cancellation, EPUB validation, SHA-256 duplicate detection, a local `Ebooks/` folder with an index, linking to the library book, Open in Apple Books, and Show in Finder.
- **Anna's Archive was evaluated and deliberately not integrated:** its collection is predominantly unauthorized copies of copyrighted books, so even a metadata-and-link connector would mainly route users to infringing downloads.
- Live-verified: *Pride and Prejudice* found in both catalogs with sizes; *Project Hail Mary* (in copyright) returns no results; ISBN lookup works; a real Standard Ebooks download validated. The live test also caught and fixed two bugs: Standard Ebooks needs its `?source=feed` URL (otherwise it serves HTML, which the validator rejected), and Gutendex timed out, so the official Gutenberg OPDS catalog replaced it.
- Adding a book from any catalog now matches an existing book by title and author, because Open Library often has several work records for one book.

### Milestone 13: README showcase
- `README.md` rewritten as a product page, using real screenshots captured from the running app with an isolated, clearly labelled demo library (`scripts/make_demo.py`). The hero is composited from those screenshots (`scripts/make_hero.py`).
- Added `docs/architecture.md`, `docs/apple-books-sync.md` and `docs/development.md`.

## 6. Sync evaluation

**Decision: versioned iCloud Drive backups (implemented, opt-in). Live multi-device sync is not enabled yet.**

| Option | Verdict |
|---|---|
| CloudKit / NSPersistentCloudKitContainer / SwiftData sync | Proper conflict-aware sync, but needs an **Apple Developer team, the iCloud entitlement, a CloudKit container and a provisioning profile**. The app is currently ad-hoc signed by `build_app.sh`, so it can't use CloudKit. It also means moving persistence from JSON to Core Data or SwiftData with a field-level merge policy. |
| Shared JSON in iCloud Drive (live) | Rejected. Two Macs writing one file produces last-writer-wins clobbering or "conflicted copy" files, and a merge applied at the wrong moment could lose notes. That's not safe enough for years of reading history. |
| **Dated snapshots in iCloud Drive** | **Implemented.** Settings → General → "Keep daily backups in iCloud Drive" writes `Folio YYYY-MM-DD.folio.json` once per day (30 kept) plus "Back Up Now". Restore on any Mac via File → Restore from Folio Backup. No entitlements needed, and the local data is never at risk. |

**To enable real sync later:**
1. Create an App ID with the iCloud (CloudKit) capability and a container, e.g. `iCloud.app.folio.reader`.
2. Sign with a Developer ID certificate and an entitlements file (`com.apple.developer.icloud-container-identifiers`, `com.apple.developer.icloud-services = CloudKit`).
3. Move the store to SwiftData or Core Data with CloudKit mirroring. Every record already carries a stable UUID and `updatedAt` (books and notes), which a per-record last-writer-wins merge can use.
4. Keep the JSON export and backups as the safety net.
