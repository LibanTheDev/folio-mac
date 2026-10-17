# Apple Books synchronization

Folio reads your Apple Books library on this Mac and keeps Folio in step: new books, confirmed reading progress, completion, and highlights. It is **strictly read-only**. Folio never opens, locks or writes Apple's files.

```
Apple Books (iPad) ──iCloud──▶ Apple Books (Mac) ──snapshot copy──▶ Folio
```

## How it works

1. **Locate.** Apple Books keeps two Core Data SQLite stores in
   `~/Library/Containers/com.apple.iBooksX/Data/Documents/`:
   - `BKLibrary/BKLibrary-*.sqlite`: one row per book in `ZBKLIBRARYASSET`.
   - `AEAnnotation/AEAnnotation_*.sqlite`: highlights, notes and reading positions in `ZAEANNOTATION`.
2. **Snapshot.** Each sync copies the store together with its `-wal` and `-shm` files into `~/Library/Caches/Folio/AppleBooksSnapshots/`, reads the copy, then deletes it. Apple Books uses write-ahead logging, so copying the WAL is what makes recent changes visible.
3. **Validate.** Folio checks the required tables and columns before reading. Optional columns are read only when present. If something required is missing (for example after a macOS update), Folio shows *Unsupported Apple Books version* in Settings and changes nothing.
4. **Merge.** The merge is forward-only and additive (see the rules below).
5. **Repeat.**
   - File watchers on both folders and on the WAL files trigger a sync about 3 seconds after Apple Books writes. This includes changes arriving from your iPad through iCloud.
   - A 5-minute timer and an app-activation check act as a safety net.
   - A fingerprint (file sizes and modification times) skips the sync when nothing changed.

## Merge rules

| What | Rule |
|---|---|
| Matching | Linked Apple Books asset ID first, then title and author. A book is never matched twice. |
| New books | Added with title, authors, genre, language, format (EPUB or PDF), description, and the date added to Apple Books. Covers and extra metadata come from Open Library. |
| Metadata | Fills only fields that are empty in Folio. |
| Progress | Apple's `ZREADINGPROGRESS` is shown as **Confirmed by Apple Books · 42% · <when>**. It is kept separate from Folio's own page log and never creates reading sessions or activity. |
| Status | Forward only: Want → Reading when Apple reports progress; Want or Reading → Read when Apple marks the book finished, using Apple's finish date only if one is recorded. Read and DNF are never changed. |
| Highlights | Imported with source attribution (annotation UUID, EPUB CFI location, colour) and the chapter title when available. Notes attached to highlights become linked reflections. |
| Your edits | A highlight you edit, tag or link in Folio is never overwritten or removed by a sync. |
| Deletions | A highlight deleted in Apple Books is removed from Folio only if you never touched it. Books removed from Apple Books are never deleted from Folio. |
| Never touched | Ratings, reviews, collections, smart shelves, tags, and your own notes. |

## Verification status

Verified on Apple Books 7.6 (build 6387), macOS 15.7, against real data in a throwaway Folio library:

| Capability | Status |
|---|---|
| Read-only snapshot reads (checksums before and after are identical) | **Verified** |
| Book import and deduplication (96 books; second sync changed nothing) | **Verified** |
| Confirmed progress (34 books) and completion with the real finish date | **Verified** |
| Highlights with attribution and chapter titles (8 imported, 7 with chapters) | **Verified** |
| Highlights for books no longer in Apple Books (skipped and counted, not guessed) | **Verified** |
| Event-driven updates (a demo store change was picked up in about 4 seconds) | **Verified with demo store** |
| Checkpointed WAL stores, missing stores, schema changes | **Verified in tests** |
| Notes attached to highlights | **Experimental** (handled and tested on fixtures; none existed on the test Mac) |
| Chapter titles (`ZFUTUREPROOFING5`, undocumented) | **Experimental** (sometimes holds an excerpt instead) |
| Changes arriving live from an iPad | **Experimental** (relies on Apple Books on the Mac writing them locally) |
| Page numbers | **Unsupported** (Apple Books stores CFI positions, not pages) |
| Start dates and reading sessions | **Unsupported** (not recorded, so not invented) |
| "Last opened" dates | **Unsupported** (on the test Mac they all equal the time iCloud populated the library) |
| Audiobooks, samples, hidden items | Skipped |
| Writing anything back to Apple Books | Never |

## Permissions

macOS may ask once whether Folio can access data from other apps. If access is blocked, Settings → Connected Libraries shows **Permission needed**, with a button that opens Privacy & Security.

## Limitations

These databases are undocumented and Apple can change them in any release. Folio validates the schema on every sync and pauses rather than guessing. The column mapping was cross-checked against the open-source [apple-books-exporter](https://github.com/ryneandal/apple-books-exporter) (MIT), whose read-only approach and status rules match. Folio differs in reading snapshot copies instead of opening Apple's live files, and in also importing highlights.
