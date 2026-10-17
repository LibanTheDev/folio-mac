import Foundation

struct AppleBooksSyncSummary: Codable, Equatable {
    var booksSeen = 0
    var booksAdded = 0
    var booksLinked = 0
    var metadataFilled = 0
    var progressConfirmed = 0
    var statusUpgraded = 0
    var highlightsAdded = 0
    var highlightsUpdated = 0
    var highlightsRemoved = 0
    var highlightsKeptLocalEdits = 0
    var highlightsUnmatched = 0
    var skippedSamplesOrHidden = 0
    var skippedAudiobooks = 0
    var annotationsAvailable = true
}

extension Library {
    /// Applies an Apple Books snapshot to the library. Additive and forward-only: never deletes books,
    /// never downgrades status, never changes ratings, reviews, collections or user-written notes.
    @discardableResult
    func mergeAppleBooks(books abBooks: [ABBook], annotations: [ABAnnotation], annotationsAvailable: Bool = true,
                         now: Date = Date()) -> AppleBooksSyncSummary {
        var s = AppleBooksSyncSummary()
        s.annotationsAvailable = annotationsAvailable
        var assetToBook: [String: UUID] = [:]
        for b in books { if let a = b.appleBooksID { assetToBook[a] = b.id } }

        for ab in abBooks {
            if ab.isAudiobook { s.skippedAudiobooks += 1; continue }
            if ab.isSample || ab.isHidden { s.skippedSamplesOrHidden += 1; continue }
            s.booksSeen += 1
            let authors = Self.splitAuthors(ab.author)

            // 1. Find the Folio book: linked ID first, then title + author.
            var id = assetToBook[ab.assetID]
            if id == nil, let match = books.first(where: { b in
                b.appleBooksID == nil && BookMatcher.titlesMatch(b.title, ab.title)
                    && (authors.isEmpty || b.authors.isEmpty || BookMatcher.authorsMatch(claimed: authors[0], actual: b.authors))
            }) {
                id = match.id
                if let mi = books.firstIndex(where: { $0.id == match.id }) { books[mi].appleBooksID = ab.assetID }
                s.booksLinked += 1
            }
            if id == nil {
                var nb = Book(title: ab.title, authors: authors, pageCount: ab.pageCount, publishYear: ab.year,
                              subjects: ab.genre.map { [$0] } ?? [])
                nb.appleBooksID = ab.assetID
                nb.dateAdded = ab.addedDate ?? now
                nb.updatedAt = now
                nb.language = ab.language
                nb.format = ab.contentType == 3 ? "PDF" : "EPUB"
                nb.synopsis = ab.description.map(Self.stripHTML).flatMap { $0.isEmpty ? nil : $0 }
                books.append(nb)
                id = nb.id
                s.booksAdded += 1
            }
            guard let bookID = id else { continue }
            assetToBook[ab.assetID] = bookID

            guard let bi = books.firstIndex(where: { $0.id == bookID }) else { continue }
            let before = books[bi]
            var b = before
            do {
                // 2. Fill only missing metadata.
                var filled = false
                if b.pageCount == nil, let p = ab.pageCount { b.pageCount = p; filled = true }
                if b.publishYear == nil, let y = ab.year { b.publishYear = y; filled = true }
                if b.language == nil, let l = ab.language { b.language = l; filled = true }
                if b.subjects.isEmpty, let g = ab.genre { b.subjects = [g]; filled = true }
                if (b.synopsis ?? "").isEmpty, let d = ab.description.map(Self.stripHTML), !d.isEmpty { b.synopsis = d; filled = true }
                if filled { s.metadataFilled += 1 }

                // 3. Confirmed progress, exactly as Apple Books reports it.
                let fraction = max(0, min(1, ab.readingProgress ?? 0))
                if ab.isFinished || fraction > 0 {
                    var ext = ExternalProgress(fraction: fraction, highWatermark: ab.highWatermark, finished: ab.isFinished,
                                               finishedDate: ab.isFinished ? ab.dateFinished : nil, observedAt: now)
                    // Keep the original observation time while the value is unchanged.
                    if let old = b.externalProgress, old.fraction == ext.fraction, old.finished == ext.finished,
                       old.finishedDate == ext.finishedDate, old.highWatermark == ext.highWatermark {
                        ext.observedAt = old.observedAt
                    }
                    b.externalProgress = ext
                    s.progressConfirmed += 1
                    if let pages = b.pageCount, pages > 0, b.status == .reading {
                        let page = Int((fraction * Double(pages)).rounded())
                        if page > b.currentPage { b.currentPage = page }
                    }
                } else {
                    b.externalProgress = nil
                }

                // 4. Forward-only status changes.
                if ab.isFinished, b.status == .wantToRead || b.status == .reading {
                    b.status = .read
                    b.dateFinished = ab.dateFinished   // nil when Apple Books didn't record a date
                    b.readCount = max(b.readCount, 1)
                    b.queueRank = nil
                    if let p = b.pageCount { b.currentPage = p }
                    s.statusUpgraded += 1
                } else if !ab.isFinished, fraction > 0, b.status == .wantToRead {
                    b.status = .reading   // start date unknown; not invented
                    b.queueRank = nil
                    s.statusUpgraded += 1
                }
            }
            if b != before {
                b.updatedAt = now
                books[bi] = b
            }
        }

        // 5. Highlights and notes.
        guard annotationsAvailable else { return s }
        let byUUID = Dictionary(annotations.map { ($0.uuid, $0) }, uniquingKeysWith: { a, b in (a.modified ?? .distantPast) >= (b.modified ?? .distantPast) ? a : b })
        var seenImported = Set<String>()
        for i in books.indices {
            for j in books[i].notes.indices {
                if let src = books[i].notes[j].source, src.kind == .appleBooks { seenImported.insert(src.externalID) }
            }
        }

        for ann in byUUID.values where ann.isHighlight || !(ann.note ?? "").isEmpty {
            guard !ann.isDeleted else { continue }
            guard let bookID = assetToBook[ann.assetID], let bi = books.firstIndex(where: { $0.id == bookID }) else {
                s.highlightsUnmatched += 1
                continue
            }
            let highlightText = (ann.selectedText ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let noteText = (ann.note ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let chapter = ann.chapter.map { String($0.trimmingCharacters(in: .whitespacesAndNewlines).prefix(80)) }.flatMap { $0.isEmpty ? nil : $0 }

            // Highlight
            if !highlightText.isEmpty {
                let key = ann.uuid
                if let ni = books[bi].notes.firstIndex(where: { $0.source?.externalID == key }) {
                    var n = books[bi].notes[ni]
                    if n.text != highlightText {
                        if n.isUntouchedImport {
                            n.text = highlightText
                            n.source?.importedText = highlightText
                            n.updated = now
                            books[bi].notes[ni] = n
                            s.highlightsUpdated += 1
                        } else if n.source?.importedText != highlightText {
                            s.highlightsKeptLocalEdits += 1
                        }
                    }
                } else {
                    var n = BookNote(created: ann.created ?? now, kind: .highlight, text: highlightText, chapter: chapter)
                    n.source = NoteSource(externalID: key, location: ann.location, style: ann.style, importedText: highlightText, importedAt: now)
                    books[bi].notes.append(n)
                    s.highlightsAdded += 1
                }
            }
            // Attached note (stored as a reflection, linked to its highlight)
            if !noteText.isEmpty {
                let key = ann.uuid + "#note"
                if let ni = books[bi].notes.firstIndex(where: { $0.source?.externalID == key }) {
                    let existing = books[bi].notes[ni]
                    if existing.text != noteText, existing.text == existing.source?.importedText, existing.tags.isEmpty {
                        books[bi].notes[ni].text = noteText
                        books[bi].notes[ni].source?.importedText = noteText
                        books[bi].notes[ni].updated = now
                        s.highlightsUpdated += 1
                    }
                } else {
                    var n = BookNote(created: ann.modified ?? ann.created ?? now, kind: .reflection, text: noteText, chapter: chapter)
                    if let hl = books[bi].notes.first(where: { $0.source?.externalID == ann.uuid }) { n.links = [hl.id] }
                    n.source = NoteSource(externalID: key, location: ann.location, style: ann.style, importedText: noteText, importedAt: now)
                    books[bi].notes.append(n)
                    s.highlightsAdded += 1
                }
            }
        }

        // 6. Remove imports deleted in Apple Books, but only if the user hasn't touched them in Folio.
        let live = Set(byUUID.values.filter { !$0.isDeleted }.flatMap { [$0.uuid, $0.uuid + "#note"] })
        for i in books.indices {
            let before = books[i].notes.count
            books[i].notes.removeAll { n in
                guard let src = n.source, src.kind == .appleBooks, !live.contains(src.externalID) else { return false }
                // Imported notes linked only to their own highlight still count as untouched.
                let ownLinkOnly = n.links.allSatisfy { lid in books[i].notes.first { $0.id == lid }?.source != nil }
                return n.text == src.importedText && n.tags.isEmpty && ownLinkOnly
            }
            s.highlightsRemoved += before - books[i].notes.count
        }
        return s
    }

    static func splitAuthors(_ raw: String?) -> [String] {
        guard let raw, !raw.trimmingCharacters(in: .whitespaces).isEmpty else { return [] }
        return raw.components(separatedBy: CharacterSet(charactersIn: "&;"))
            .flatMap { $0.components(separatedBy: " and ") }
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    static func stripHTML(_ s: String) -> String {
        s.replacingOccurrences(of: "<br\\s*/?>", with: "\n", options: .regularExpression)
            .replacingOccurrences(of: "</p>", with: "\n\n")
            .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "&amp;", with: "&").replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'").replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: #"\n{3,}"#, with: "\n\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
