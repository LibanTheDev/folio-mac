# Development

## Requirements

- macOS 14 Sonoma or later (developed on macOS 15.7, Apple Silicon)
- Xcode Command Line Tools with Swift 6.1 or newer (`xcode-select --install`). The full Xcode app isn't required.
- Python 3 (optional), only for the demo and screenshot scripts. `make_hero.py` also needs Pillow.

There are no package dependencies to install. Swift Package Manager builds everything from `Package.swift`.

## Build and run

```bash
gh repo clone LibanTheDev/folio-mac && cd folio-mac
swift build                 # debug build
./build_app.sh              # release build → Folio.app (icon, Info.plist, ad-hoc signature)
open Folio.app
```

## Tests

```bash
swift test                                                   # full offline suite
FOLIO_NETWORK_TESTS=1 swift test --filter "NetworkTests|LiveEbookTests"   # Open Library, Standard Ebooks, Gutenberg
FOLIO_APPLE_BOOKS_LIVE=1 swift test --filter LiveAppleBooksTests         # reads your real Apple Books data (read-only; merges into a temp library)
FOLIO_ANTHROPIC_KEY=sk-ant-… swift test --filter LiveAITests              # a few cents of API usage
```

## Demo environment

Run Folio against an isolated, clearly labelled sample library and a synthetic Apple Books store. Your own data is never touched:

```bash
python3 scripts/make_demo.py /tmp/folio-demo
open -n --env FOLIO_DATA_DIR=/tmp/folio-demo/library \
        --env FOLIO_APPLE_BOOKS_DIR=/tmp/folio-demo/applebooks Folio.app
```

All README screenshots were captured this way. `python3 scripts/make_hero.py` rebuilds the hero image from them.

## Optional integrations

| Integration | Setup |
|---|---|
| AI (recommendations, Ask Folio) | Settings → AI. Choose Anthropic (key stored in your Keychain) or an OpenAI-compatible server such as local Ollama. Off by default. |
| Apple Books | On by default. Settings → Connected Libraries shows status. macOS may ask once for access to other apps' data. |
| Reading reminders | Settings → Reminders. macOS asks for notification permission. |
| iCloud Drive backups | Settings → General. |

## Conventions

- UI uses only `DS` tokens and the glass primitives in `DesignSystem/`. Animation goes through `Motion` so Reduce Motion is respected.
- Every schema addition decodes with a default (`KeyedDecodingContainer.value(_:_:)`).
- Don't commit secrets, `library.json`, or anything under `.build/`; `.gitignore` covers them.
