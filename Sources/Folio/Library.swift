import AppKit
import Combine
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class Library: ObservableObject {
    @Published var books: [Book] = []
    @Published var goals: [Int: Int] = [:]
    /// User-created shelves (tags) that exist even before any book is on them.
    @Published var shelves: [String] = []

    // UI requests coming from menu commands.
    @Published var showingAddBook = false
    var addBookStatus: ReadingStatus = .wantToRead
    @Published var alertMessage: String?

    private var cancellables = Set<AnyCancellable>()
    private let fileURL: URL

    init() {
        let dir = ProcessInfo.processInfo.environment["FOLIO_DATA_DIR"].map { URL(fileURLWithPath: $0) }
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("Folio", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("library.json")
        load()

        $books.combineLatest($goals, $shelves)
            .dropFirst()
            .debounce(for: .milliseconds(400), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.save() }
            .store(in: &cancellables)
    }

    // MARK: Persistence

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let file = try? decoder.decode(LibraryFile.self, from: data) {
            books = file.books
            goals = file.goals
            shelves = file.shelves ?? []
        }
    }

    func save() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(LibraryFile(books: books, goals: goals, shelves: shelves)) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    // MARK: Queries

    func book(_ id: UUID) -> Book? { books.first { $0.id == id } }

    func books(in status: ReadingStatus) -> [Book] { books.filter { $0.status == status } }

    var allTags: [String] {
        Array(Set(books.flatMap(\.tags) + shelves)).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    func contains(workKey: String) -> Book? { books.first { $0.olWorkKey == workKey } }

    func finished(in year: Int) -> [Book] {
        let cal = Calendar.current
        return books.filter { $0.status == .read && $0.dateFinished.map { cal.component(.year, from: $0) == year } == true }
    }

    var currentYear: Int { Calendar.current.component(.year, from: Date()) }

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
        books[i] = book
    }

    func modify(_ id: UUID, _ change: (inout Book) -> Void) {
        guard let i = books.firstIndex(where: { $0.id == id }) else { return }
        change(&books[i])
    }

    @discardableResult
    func add(_ book: Book, status: ReadingStatus) -> UUID {
        if let key = book.olWorkKey, let existing = contains(workKey: key) {
            setStatus(existing.id, status)
            return existing.id
        }
        var b = book
        b.dateAdded = Date()
        books.append(b)
        setStatus(b.id, status)
        return b.id
    }

    func setStatus(_ id: UUID, _ status: ReadingStatus) {
        modify(id) { b in
            guard b.status != status else { return }
            b.status = status
            switch status {
            case .reading:
                if b.dateStarted == nil || b.dateFinished != nil { b.dateStarted = Date(); b.dateFinished = nil }
            case .read:
                if b.dateStarted == nil { b.dateStarted = Date() }
                b.dateFinished = Date()
                b.readCount = max(b.readCount, 0) + 1
                if let p = b.pageCount { b.currentPage = p }
            case .wantToRead, .dnf:
                break
            }
        }
    }

    func logProgress(_ id: UUID, page: Int) {
        modify(id) { b in
            let clamped = max(0, b.pageCount.map { min(page, $0) } ?? page)
            b.currentPage = clamped
            b.progressLog.append(ProgressEntry(date: Date(), page: clamped))
            if b.status == .wantToRead { b.status = .reading; b.dateStarted = b.dateStarted ?? Date() }
        }
        if let b = book(id), let pages = b.pageCount, b.currentPage >= pages, b.status == .reading {
            setStatus(id, .read)
        }
    }

    func startReread(_ id: UUID) {
        modify(id) { b in
            b.status = .reading
            b.dateStarted = Date()
            b.dateFinished = nil
            b.currentPage = 0
        }
    }

    func presentAddBook(_ status: ReadingStatus = .wantToRead) {
        addBookStatus = status
        showingAddBook = true
    }

    static func shelfSlug(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespaces).lowercased().replacingOccurrences(of: " ", with: "-")
    }

    func createShelf(_ name: String) {
        let slug = Self.shelfSlug(name)
        guard !slug.isEmpty, !allTags.contains(slug) else { return }
        shelves.append(slug)
    }

    func deleteShelf(_ tag: String) {
        shelves.removeAll { $0 == tag }
        for i in books.indices { books[i].tags.removeAll { $0 == tag } }
    }

    func delete(_ ids: Set<UUID>) {
        books.removeAll { ids.contains($0.id) }
    }

    /// Fills in cover, page count and synopsis from Open Library for books that lack them (e.g. imported ones).
    func enrich(_ id: UUID) async {
        guard var b = book(id) else { return }
        if b.olWorkKey == nil || b.coverID == nil {
            if let doc = await OpenLibrary.lookup(isbn: b.isbn, title: b.title, author: b.authors.first) {
                b.olWorkKey = b.olWorkKey ?? doc.key
                b.coverID = b.coverID ?? doc.cover_i
                b.pageCount = b.pageCount ?? doc.number_of_pages_median
                b.publishYear = b.publishYear ?? doc.first_publish_year
                if b.subjects.isEmpty { b.subjects = Array((doc.subject ?? []).prefix(8)) }
            }
        }
        if b.synopsis == nil, let key = b.olWorkKey {
            b.synopsis = await OpenLibrary.description(workKey: key) ?? ""
        }
        // Only write back the enrichment fields so we never clobber edits made meanwhile.
        modify(id) { cur in
            cur.olWorkKey = b.olWorkKey; cur.coverID = b.coverID; cur.pageCount = cur.pageCount ?? b.pageCount
            cur.publishYear = b.publishYear; cur.subjects = b.subjects; cur.synopsis = b.synopsis
        }
    }

    // MARK: Import / Export

    func importGoodreads() {
        let panel = NSOpenPanel()
        panel.title = "Import Goodreads Library"
        panel.message = "Choose the CSV from Goodreads → My Books → Import and export → Export Library."
        panel.allowedContentTypes = [.commaSeparatedText, .plainText]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let text = try String(contentsOf: url, encoding: .utf8)
            let imported = try GoodreadsCSV.parse(text)
            var added = 0, updated = 0
            for var b in imported {
                if let i = books.firstIndex(where: { existing in
                    (b.isbn != nil && existing.isbn == b.isbn) ||
                    (existing.title.lowercased() == b.title.lowercased() && existing.authors.first == b.authors.first)
                }) {
                    b.id = books[i].id
                    b.coverID = books[i].coverID
                    b.olWorkKey = books[i].olWorkKey
                    b.synopsis = books[i].synopsis
                    b.notes = books[i].notes + b.notes
                    books[i] = b
                    updated += 1
                } else {
                    books.append(b)
                    added += 1
                }
            }
            alertMessage = "Imported \(added) new book\(added == 1 ? "" : "s")" + (updated > 0 ? " and updated \(updated)." : ".")
            Task { await enrichAll() }
        } catch {
            alertMessage = "Couldn't import that file: \(error.localizedDescription)"
        }
    }

    private func enrichAll() async {
        for id in books.filter({ $0.coverID == nil && $0.olWorkKey == nil }).map(\.id) {
            await enrich(id)
        }
    }

    func exportCSV() {
        let panel = NSSavePanel()
        panel.title = "Export Library"
        panel.nameFieldStringValue = "Folio Library.csv"
        panel.allowedContentTypes = [.commaSeparatedText]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try GoodreadsCSV.export(books).write(to: url, atomically: true, encoding: .utf8)
            alertMessage = "Exported \(books.count) books in Goodreads-compatible CSV format."
        } catch {
            alertMessage = "Export failed: \(error.localizedDescription)"
        }
    }
}
