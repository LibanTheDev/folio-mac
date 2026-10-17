import Combine
import Foundation
import SwiftUI

@MainActor
final class Library: ObservableObject {
    @Published var books: [Book] = []
    @Published var goals: [Int: Int] = [:]
    /// Tag names that exist even before any book carries them.
    @Published var tagNames: [String] = []
    @Published var shelves: [Shelf] = []
    @Published var sessions: [ReadingSession] = []
    @Published var activeSession: ActiveSession?
    @Published var dismissedRecommendations: [String] = []
    @Published var interests: [String] = []

    // UI requests coming from menu commands.
    @Published var showingAddBook = false
    var addBookStatus: ReadingStatus = .wantToRead
    @Published var alertMessage: String?
    /// Set when the library file could not be read; saving is disabled to protect it.
    @Published private(set) var loadError: String?

    private var cancellables = Set<AnyCancellable>()
    let store: LibraryStore

    init(directory: URL? = nil, autosave: Bool = true) {
        let dir = directory
            ?? ProcessInfo.processInfo.environment["FOLIO_DATA_DIR"].map { URL(fileURLWithPath: $0) }
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("Folio", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        store = LibraryStore(directory: dir)
        load()
        guard autosave else { return }
        store.dailyBackupIfNeeded()
        if UserDefaults.standard.bool(forKey: "backup.icloud"), loadError == nil,
           let data = try? LibraryStore.encoder().encode(snapshot) {
            _ = try? CloudBackup.backup(data)
        }

        Publishers.MergeMany(
            $books.map { _ in () }.eraseToAnyPublisher(),
            $goals.map { _ in () }.eraseToAnyPublisher(),
            $tagNames.map { _ in () }.eraseToAnyPublisher(),
            $shelves.map { _ in () }.eraseToAnyPublisher(),
            $sessions.map { _ in () }.eraseToAnyPublisher(),
            $activeSession.map { _ in () }.eraseToAnyPublisher(),
            $dismissedRecommendations.map { _ in () }.eraseToAnyPublisher(),
            $interests.map { _ in () }.eraseToAnyPublisher()
        )
        .dropFirst(8)
        .debounce(for: .milliseconds(400), scheduler: RunLoop.main)
        .sink { [weak self] in self?.save() }
        .store(in: &cancellables)
    }

    // MARK: Persistence

    private func load() {
        do {
            switch try store.load() {
            case .empty:
                break
            case .loaded(let file, let migratedFrom):
                apply(file)
                if migratedFrom != nil { save() }
            }
        } catch {
            loadError = "Folio couldn't read your library file, so it hasn't been changed. A copy was placed in the Backups folder. (\(error.localizedDescription))"
            alertMessage = loadError
        }
    }

    private func apply(_ file: LibraryFile) {
        books = file.books
        goals = file.goals
        tagNames = file.tagNames
        shelves = file.shelves
        sessions = file.sessions
        activeSession = file.activeSession
        dismissedRecommendations = file.dismissedRecommendations
        interests = file.interests
    }

    var snapshot: LibraryFile {
        var f = LibraryFile()
        f.books = books
        f.goals = goals
        f.tagNames = tagNames
        f.shelves = shelves
        f.sessions = sessions
        f.activeSession = activeSession
        f.dismissedRecommendations = dismissedRecommendations
        f.interests = interests
        return f
    }

    func save() {
        guard loadError == nil else { return }
        do { try store.save(snapshot) } catch {
            alertMessage = "Couldn't save your library: \(error.localizedDescription)"
        }
    }

    /// Replaces the whole library with a backup, after backing up the current state.
    func restore(from file: LibraryFile) {
        if let data = try? LibraryStore.encoder().encode(snapshot) {
            try? store.backup(data, label: "before-restore")
        }
        loadError = nil
        apply(file)
        save()
    }

    // MARK: Queries

    func book(_ id: UUID) -> Book? { books.first { $0.id == id } }

    func books(in status: ReadingStatus) -> [Book] { books.filter { $0.status == status } }

    var allTags: [String] {
        Array(Set(books.flatMap(\.tags) + tagNames)).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    var allAuthors: [String] {
        Array(Set(books.flatMap(\.authors))).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    var allGenres: [(name: String, count: Int)] {
        Dictionary(grouping: books.flatMap(\.genres), by: { $0 })
            .map { ($0.key, $0.value.count) }
            .sorted { $0.count > $1.count || ($0.count == $1.count && $0.name < $1.name) }
    }

    func contains(workKey: String) -> Book? { books.first { $0.olWorkKey == workKey } }

    /// The library's copy of a book: same Open Library work, or same title and author (catalogs often
    /// have several records for one book).
    func existing(matching b: Book) -> Book? {
        if let key = b.olWorkKey, let hit = contains(workKey: key) { return hit }
        return books.first { mine in
            BookMatcher.titlesMatch(mine.title, b.title)
                && (b.authors.first.map { BookMatcher.authorsMatch(claimed: $0, actual: mine.authors) } ?? mine.authors.isEmpty)
        }
    }

    func finished(in year: Int) -> [Book] {
        let cal = Calendar.current
        return books.filter { $0.status == .read && $0.dateFinished.map { cal.component(.year, from: $0) == year } == true }
    }

    var currentYear: Int { Calendar.current.component(.year, from: Date()) }

    func shelf(_ id: UUID) -> Shelf? { shelves.first { $0.id == id } }

    func books(on shelf: Shelf) -> [Book] {
        switch shelf.kind {
        case .manual:
            let byID = Dictionary(uniqueKeysWithValues: books.map { ($0.id, $0) })
            return shelf.bookIDs.compactMap { byID[$0] }
        case .smart:
            let now = Date()
            return books.filter { shelf.contains($0, now: now) }
        }
    }

    /// Want-to-read books in queue order: ranked ones first, then the rest by date added (newest first).
    var upNext: [Book] {
        books(in: .wantToRead).sorted { a, b in
            switch (a.queueRank, b.queueRank) {
            case let (x?, y?): return x < y
            case (_?, nil): return true
            case (nil, _?): return false
            default: return a.dateAdded > b.dateAdded
            }
        }
    }

    var allNotes: [NoteRef] {
        books.flatMap { b in b.notes.map { NoteRef(note: $0, book: b) } }
            .sorted { $0.note.updated > $1.note.updated }
    }

    func note(_ id: UUID) -> NoteRef? {
        for b in books { if let n = b.notes.first(where: { $0.id == id }) { return NoteRef(note: n, book: b) } }
        return nil
    }

    // MARK: Mutations

    func binding(_ id: UUID) -> Binding<Book>? {
        guard let fallback = book(id) else { return nil }
        return Binding(
            get: { [weak self] in self?.book(id) ?? fallback },
            set: { [weak self] new in self?.update(new) }
        )
    }

    func update(_ book: Book) {
        guard let i = books.firstIndex(where: { $0.id == book.id }) else { return }
        var b = book
        if b != books[i] { b.updatedAt = Date() }
        books[i] = b
    }

    func modify(_ id: UUID, _ change: (inout Book) -> Void) {
        guard let i = books.firstIndex(where: { $0.id == id }) else { return }
        var b = books[i]
        change(&b)
        b.updatedAt = Date()
        books[i] = b
    }

    @discardableResult
    func add(_ book: Book, status: ReadingStatus) -> UUID {
        if let existing = existing(matching: book) {
            setStatus(existing.id, status)
            return existing.id
        }
        var b = book
        b.dateAdded = Date()
        b.updatedAt = Date()
        books.append(b)
        setStatus(b.id, status)
        return b.id
    }

    func setStatus(_ id: UUID, _ status: ReadingStatus, at now: Date = Date()) {
        modify(id) { b in
            guard b.status != status else { return }
            let previous = b.status
            b.status = status
            switch status {
            case .reading:
                if previous == .read {
                    // Moving a finished book back to reading starts a reread; keep the finished pass.
                    b.history.append(ReadThrough(started: b.dateStarted, finished: b.dateFinished, rating: b.rating))
                    b.dateStarted = now
                    b.dateFinished = nil
                    b.currentPage = 0
                } else if b.dateStarted == nil {
                    b.dateStarted = now
                }
            case .read:
                if b.dateStarted == nil { b.dateStarted = now }
                b.dateFinished = now
                b.readCount = max(b.readCount, b.history.filter { $0.outcome == .finished }.count) + 1
                if let p = b.pageCount { b.currentPage = p }
                b.queueRank = nil
            case .dnf:
                b.queueRank = nil
            case .wantToRead:
                break
            }
        }
        if status != .reading, activeSession?.bookID == id { discardSession() }
    }

    func logProgress(_ id: UUID, page: Int, at now: Date = Date()) {
        modify(id) { b in
            let clamped = max(0, b.pageCount.map { min(page, $0) } ?? page)
            b.currentPage = clamped
            b.progressLog.append(ProgressEntry(date: now, page: clamped))
            if b.status == .wantToRead {
                b.status = .reading
                b.dateStarted = b.dateStarted ?? now
                b.queueRank = nil
            }
        }
        if let b = book(id), let pages = b.pageCount, b.currentPage >= pages, b.status == .reading {
            setStatus(id, .read, at: now)
        }
    }

    /// Archives the current read-through into history and starts a new one.
    func startReread(_ id: UUID, at now: Date = Date()) {
        modify(id) { b in
            if b.dateStarted != nil || b.dateFinished != nil {
                b.history.append(ReadThrough(started: b.dateStarted, finished: b.dateFinished,
                                             outcome: b.status == .dnf ? .abandoned : .finished, rating: b.rating))
            }
            b.status = .reading
            b.dateStarted = now
            b.dateFinished = nil
            b.currentPage = 0
        }
    }

    func delete(_ ids: Set<UUID>) {
        books.removeAll { ids.contains($0.id) }
        sessions.removeAll { ids.contains($0.bookID) }
        for i in shelves.indices { shelves[i].bookIDs.removeAll { ids.contains($0) } }
        if let a = activeSession, ids.contains(a.bookID) { activeSession = nil }
        // Drop links pointing at notes that no longer exist.
        let live = Set(books.flatMap { $0.notes.map(\.id) })
        for i in books.indices {
            for j in books[i].notes.indices { books[i].notes[j].links.removeAll { !live.contains($0) } }
        }
    }

    // MARK: Up Next queue

    /// Moves `id` to position `index` within the Up Next queue and renumbers ranks.
    func moveInQueue(_ id: UUID, to index: Int) {
        var order = upNext.map(\.id)
        guard let from = order.firstIndex(of: id) else { return }
        order.remove(at: from)
        order.insert(id, at: max(0, min(index, order.count)))
        for (rank, bookID) in order.enumerated() {
            modify(bookID) { $0.queueRank = Double(rank) }
        }
    }

    // MARK: Tags

    func presentAddBook(_ status: ReadingStatus = .wantToRead) {
        addBookStatus = status
        showingAddBook = true
    }

    static func tagSlug(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespaces).lowercased().replacingOccurrences(of: " ", with: "-")
    }

    func createTag(_ name: String) {
        let slug = Self.tagSlug(name)
        guard !slug.isEmpty, !allTags.contains(slug) else { return }
        tagNames.append(slug)
    }

    func deleteTag(_ tag: String) {
        tagNames.removeAll { $0 == tag }
        for i in books.indices where books[i].tags.contains(tag) { books[i].tags.removeAll { $0 == tag } }
    }

    func renameTag(_ tag: String, to newName: String) {
        let slug = Self.tagSlug(newName)
        guard !slug.isEmpty, slug != tag else { return }
        tagNames = tagNames.map { $0 == tag ? slug : $0 }
        for i in books.indices where books[i].tags.contains(tag) {
            books[i].tags = Array(NSOrderedSet(array: books[i].tags.map { $0 == tag ? slug : $0 })) as? [String] ?? books[i].tags
        }
    }

    // MARK: Shelves (collections and smart shelves)

    @discardableResult
    func addShelf(_ shelf: Shelf) -> UUID {
        shelves.append(shelf)
        return shelf.id
    }

    func updateShelf(_ shelf: Shelf) {
        guard let i = shelves.firstIndex(where: { $0.id == shelf.id }) else { return }
        shelves[i] = shelf
    }

    func deleteShelf(_ id: UUID) { shelves.removeAll { $0.id == id } }

    func moveShelf(_ id: UUID, by offset: Int) {
        guard let i = shelves.firstIndex(where: { $0.id == id }) else { return }
        let j = max(0, min(shelves.count - 1, i + offset))
        guard i != j else { return }
        shelves.swapAt(i, j)
    }

    func moveShelf(_ id: UUID, before target: UUID) {
        guard id != target, let from = shelves.firstIndex(where: { $0.id == id }) else { return }
        let s = shelves.remove(at: from)
        let to = shelves.firstIndex(where: { $0.id == target }) ?? shelves.count
        shelves.insert(s, at: to)
    }

    func add(_ bookIDs: [UUID], toShelf shelfID: UUID) {
        guard let i = shelves.firstIndex(where: { $0.id == shelfID }), shelves[i].kind == .manual else { return }
        for id in bookIDs where !shelves[i].bookIDs.contains(id) { shelves[i].bookIDs.append(id) }
    }

    func remove(_ bookIDs: [UUID], fromShelf shelfID: UUID) {
        guard let i = shelves.firstIndex(where: { $0.id == shelfID }) else { return }
        shelves[i].bookIDs.removeAll { bookIDs.contains($0) }
    }

    func manualShelves(containing id: UUID) -> [Shelf] {
        shelves.filter { $0.kind == .manual && $0.bookIDs.contains(id) }
    }

    // MARK: Enrichment

    /// Fills in cover, page count and synopsis from Open Library for books that lack them (e.g. imported ones).
    func enrich(_ id: UUID) async {
        guard var b = book(id) else { return }
        if b.olWorkKey == nil || b.coverID == nil {
            if let doc = await OpenLibrary.lookup(isbn: b.isbn, title: b.title, author: b.authors.first) {
                b.olWorkKey = b.olWorkKey ?? doc.key
                b.coverID = b.coverID ?? doc.cover_i
                b.pageCount = b.pageCount ?? doc.number_of_pages_median
                b.publishYear = b.publishYear ?? doc.first_publish_year
                if b.subjects.isEmpty { b.subjects = Array((doc.subject ?? []).prefix(12)) }
            }
        }
        if b.synopsis == nil, let key = b.olWorkKey {
            b.synopsis = await OpenLibrary.description(workKey: key) ?? ""
        }
        // Only write back the enrichment fields so we never clobber edits made meanwhile.
        guard let i = books.firstIndex(where: { $0.id == id }) else { return }
        books[i].olWorkKey = b.olWorkKey
        books[i].coverID = b.coverID
        books[i].pageCount = books[i].pageCount ?? b.pageCount
        books[i].publishYear = books[i].publishYear ?? b.publishYear
        if books[i].subjects.isEmpty { books[i].subjects = b.subjects }
        books[i].synopsis = b.synopsis
    }

    func enrichAll() async {
        for id in books.filter({ $0.coverID == nil && $0.olWorkKey == nil }).map(\.id) {
            await enrich(id)
        }
    }

    // MARK: Goodreads merge

    struct ImportSummary: Equatable { var added = 0, updated = 0 }

    /// Merges imported Goodreads books. Goodreads-owned fields (status, rating, review, dates, shelves)
    /// are refreshed; Folio-only data (notes, sessions, history, covers, queue, favourites) is preserved.
    @discardableResult
    func merge(imported: [Book]) -> ImportSummary {
        var summary = ImportSummary()
        for b in imported {
            if let i = books.firstIndex(where: { existing in
                (b.isbn != nil && existing.isbn == b.isbn) ||
                (existing.title.lowercased() == b.title.lowercased() && existing.authors.first == b.authors.first)
            }) {
                var cur = books[i]
                cur.status = b.status
                cur.rating = b.rating ?? cur.rating
                if !b.review.isEmpty { cur.review = b.review }
                cur.tags = Array(NSOrderedSet(array: cur.tags + b.tags)) as? [String] ?? cur.tags
                cur.dateFinished = b.dateFinished ?? cur.dateFinished
                cur.readCount = max(cur.readCount, b.readCount)
                cur.pageCount = cur.pageCount ?? b.pageCount
                cur.publishYear = cur.publishYear ?? b.publishYear
                cur.publisher = cur.publisher ?? b.publisher
                cur.isbn = cur.isbn ?? b.isbn
                let existingTexts = Set(cur.notes.map(\.text))
                cur.notes += b.notes.filter { !existingTexts.contains($0.text) }
                if cur.status == .read, let p = cur.pageCount { cur.currentPage = p }
                cur.updatedAt = Date()
                books[i] = cur
                summary.updated += 1
            } else {
                books.append(b)
                summary.added += 1
            }
        }
        return summary
    }
}
