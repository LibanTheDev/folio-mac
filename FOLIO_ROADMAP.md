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
| 3 | Library gallery, smart shelves, book detail, rereads | ⏳ | |
| 4 | Live home dashboard | ⏳ | |
| 5 | Reading sessions and analytics | ⏳ | |
| 6 | Personal knowledge vault and search | ⏳ | |
| 7 | AI-powered discovery | ⏳ | |
| 8 | Ask Folio and knowledge graph | ⏳ | |
| 9 | Command palette, notifications, backups/sync, export | ⏳ | |
| 10 | Final QA | ⏳ | |

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

## 6. Sync evaluation

To be completed in milestone 9.
