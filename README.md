# Folio

A native macOS reading tracker that aims to be a better Goodreads: fast, private, and built for the Mac.

## Run it
Double-click `Folio.app`, or rebuild from source with `./build_app.sh` (needs Xcode Command Line Tools, macOS 14+).

## Why it's better than Goodreads
- **Half-star ratings** (finally).
- **Did Not Finish** shelf, built in.
- **One-click Goodreads import**: My Books → Import and export → Export Library, then File → Import Goodreads Library (⇧⌘I). It keeps your ratings, shelves (as tags), reviews, dates, read counts and private notes. Covers and descriptions are filled in automatically.
- **Your data stays yours**: everything lives in `~/Library/Application Support/Folio/library.json`. No account, ads, or feed. File → Export (⇧⌘E) writes a Goodreads-compatible CSV.
- **Progress tracking**: page logging, a "days left at your pace" estimate, and a daily reading streak.
- **Notes & quotes** per book, with page numbers.
- **Stats**: yearly goal with an ahead/behind pace check, books per month, rating distribution, highlights, and top authors.
- **Re-reads**: start a re-read and the read count is tracked.
- **Native Mac UI**: warm "paper" design (with a Night theme under View → Appearance), a kanban board you can drag books across, a cover grid and a sortable table, an inspector panel with collapsible sections and "Books by this author", custom shelves, quick filters, and keyboard shortcuts (⌘N add book, ⌘1–4 pages, ⌘F search, ⌥⌘I inspector).

Book data and covers come from [Open Library](https://openlibrary.org) (free, no API key).
