import Foundation
import Testing
@testable import Folio

@MainActor @Suite struct LibraryTests {
    func makeLibrary() -> Library {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("folio-lib-\(UUID().uuidString)")
        return Library(directory: dir, autosave: false)
    }

    @Test func rereadKeepsPreviousReadThrough() throws {
        let lib = makeLibrary()
        var b = Book(title: "Dune", authors: ["Frank Herbert"], pageCount: 600)
        b.status = .read
        b.dateStarted = Date(timeIntervalSince1970: 1_000)
        b.dateFinished = Date(timeIntervalSince1970: 2_000)
        b.rating = 5
        b.readCount = 1
        lib.books = [b]
        lib.startReread(b.id)
        let after = try #require(lib.book(b.id))
        #expect(after.status == .reading)
        #expect(after.history.count == 1)
        #expect(after.history[0].finished == Date(timeIntervalSince1970: 2_000))
        #expect(after.history[0].rating == 5)
        lib.setStatus(b.id, .read)
        #expect(lib.book(b.id)?.readCount == 2)
        #expect(lib.book(b.id)?.allReadThroughs.count == 2)
    }

    @Test func movingFinishedBookBackToReadingArchivesIt() throws {
        let lib = makeLibrary()
        var b = Book(title: "X", authors: [])
        b.status = .read
        b.dateFinished = Date(timeIntervalSince1970: 5_000)
        lib.books = [b]
        lib.setStatus(b.id, .reading)
        #expect(lib.book(b.id)?.history.count == 1)
        #expect(lib.book(b.id)?.dateFinished == nil)
    }

    @Test func goodreadsReimportPreservesFolioData() throws {
        let lib = makeLibrary()
        var mine = Book(title: "Dune", authors: ["Frank Herbert"], isbn: "9780441172719")
        mine.notes = [BookNote(kind: .highlight, text: "Fear is the mind-killer.")]
        mine.favorite = true
        mine.coverID = 42
        lib.books = [mine]
        var imported = Book(title: "Dune", authors: ["Frank Herbert"], isbn: "9780441172719")
        imported.status = .read
        imported.rating = 5
        imported.tags = ["classics"]
        let summary = lib.merge(imported: [imported, Book(title: "New One", authors: ["Someone"])])
        #expect(summary == .init(added: 1, updated: 1))
        let merged = try #require(lib.books.first { $0.title == "Dune" })
        #expect(merged.status == .read)
        #expect(merged.rating == 5)
        #expect(merged.favorite)
        #expect(merged.coverID == 42)
        #expect(merged.notes.count == 1)
        #expect(merged.tags == ["classics"])
    }

    @Test func upNextQueueReorders() {
        let lib = makeLibrary()
        let books = (0..<3).map { Book(title: "B\($0)", authors: []) }
        lib.books = books
        lib.moveInQueue(books[2].id, to: 0)
        #expect(lib.upNext.map(\.title) == ["B2", "B0", "B1"] || lib.upNext.first?.title == "B2")
        lib.moveInQueue(books[0].id, to: 2)
        #expect(lib.upNext.last?.id == books[0].id)
    }

    @Test func deletingBookCleansShelvesSessionsAndLinks() {
        let lib = makeLibrary()
        var a = Book(title: "A", authors: [])
        var b = Book(title: "B", authors: [])
        let noteA = BookNote(text: "a")
        var noteB = BookNote(text: "b")
        noteB.links = [noteA.id]
        a.notes = [noteA]
        b.notes = [noteB]
        lib.books = [a, b]
        lib.shelves = [Shelf(name: "C", bookIDs: [a.id, b.id])]
        lib.sessions = [ReadingSession(bookID: a.id, start: Date(), duration: 60, startPage: 0, endPage: 5)]
        lib.delete([a.id])
        #expect(lib.shelves[0].bookIDs == [b.id])
        #expect(lib.sessions.isEmpty)
        #expect(lib.books[0].notes[0].links.isEmpty)
    }

    @Test func tagRenameAndDelete() {
        let lib = makeLibrary()
        var a = Book(title: "A", authors: [])
        a.tags = ["sci-fi", "fun"]
        lib.books = [a]
        lib.renameTag("sci-fi", to: "Science Fiction")
        #expect(lib.books[0].tags == ["science-fiction", "fun"])
        lib.deleteTag("fun")
        #expect(lib.books[0].tags == ["science-fiction"])
    }
}

@Suite struct ShelfAndFilterTests {
    func book(_ title: String, status: ReadingStatus = .read, rating: Double? = nil, pages: Int? = nil,
              finished: String? = nil, subjects: [String] = [], tags: [String] = [], author: String = "A") -> Book {
        var b = Book(title: title, authors: [author], pageCount: pages, subjects: subjects)
        b.status = status
        b.rating = rating
        b.tags = tags
        if let finished {
            let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
            b.dateFinished = f.date(from: finished)
        }
        return b
    }

    @Test func smartShelfTemplatesEvaluate() {
        let best = Shelf.templates(year: 2026)[0]
        #expect(best.contains(book("Great", rating: 4.5, finished: "2026-03-01")))
        #expect(!best.contains(book("Meh", rating: 3, finished: "2026-03-01")))
        #expect(!best.contains(book("Old", rating: 5, finished: "2025-03-01")))
        let long = Shelf.templates(year: 2026).first { $0.name == "Long Reads" }!
        #expect(long.contains(book("Big", pages: 900)))
        #expect(!long.contains(book("Small", pages: 120)))
        let bizBio = Shelf.templates(year: 2026).first { $0.name == "Business Biographies" }!
        #expect(bizBio.contains(book("Tycoon", subjects: ["Biography", "Business"])))
        #expect(!bizBio.contains(book("Novel", subjects: ["Fantasy"])))
        let invest = Shelf.templates(year: 2026).first { $0.name == "Investing" }!
        #expect(invest.contains(book("Tagged", tags: ["investing"])))
    }

    @Test func emptySmartShelfMatchesNothing() {
        #expect(!Shelf(name: "Empty", kind: .smart).contains(book("x")))
    }

    @Test func filterFacetsCombine() {
        let books = [
            book("A", status: .read, rating: 5, pages: 300, subjects: ["Fantasy"], author: "Le Guin"),
            book("B", status: .reading, rating: nil, pages: 600, subjects: ["History"], author: "Caro"),
            book("C", status: .read, rating: 3, pages: 200, subjects: ["Fantasy"], author: "Caro"),
        ]
        var f = LibraryFilter()
        f.genres = ["Fantasy"]
        #expect(books.filter { f.matches($0, shelves: []) }.map(\.title) == ["A", "C"])
        f.minRating = 4
        #expect(books.filter { f.matches($0, shelves: []) }.map(\.title) == ["A"])
        f = LibraryFilter()
        f.authors = ["Caro"]
        f.minPages = 500
        #expect(books.filter { f.matches($0, shelves: []) }.map(\.title) == ["B"])
        f = LibraryFilter()
        f.statuses = [.read, .reading]
        f.unratedOnly = true
        #expect(books.filter { f.matches($0, shelves: []) }.map(\.title) == ["B"])
    }

    @Test func filterTokensRemoveCleanly() {
        var f = LibraryFilter()
        f.statuses = [.read]
        f.genres = ["Fantasy"]
        f.minPages = 100
        let tokens = f.tokens(shelfName: { _ in nil })
        #expect(tokens.count == 3)
        for t in tokens { f.remove(t.id) }
        #expect(f.isEmpty)
    }

    @Test func relatedBooksPreferSameAuthor() {
        let target = book("T", subjects: ["Fantasy"], author: "Le Guin")
        let sameAuthor = book("S", subjects: [], author: "Le Guin")
        let sameGenre = book("G", subjects: ["Fantasy"], author: "Other")
        let unrelated = book("U", subjects: ["Cooking"], author: "Chef")
        let related = Related.books(for: target, in: [target, sameGenre, unrelated, sameAuthor], shelves: [])
        #expect(related.map(\.title) == ["S", "G"])
    }
}

@Suite struct ForecastTests {
    let cal = Calendar(identifier: .gregorian)

    func day(_ n: Int, from base: Date) -> Date { cal.date(byAdding: .day, value: n, to: base)! }

    @Test func insufficientWithoutRecordedReading() {
        var b = Book(title: "X", authors: [], pageCount: 300)
        b.status = .reading
        b.currentPage = 120  // e.g. imported, no log
        let f = ReadingForecast.make(book: b, sessions: [], calendar: cal)
        #expect(f.confidence == .insufficient)
        #expect(f.finish == nil)
        #expect(f.pagesRemaining == 180)
    }

    @Test func steadyPaceGivesGoodEstimate() throws {
        let now = cal.startOfDay(for: Date())
        var b = Book(title: "X", authors: [], pageCount: 300)
        b.status = .reading
        b.dateStarted = day(-9, from: now)
        b.progressLog = (0..<10).map { i in ProgressEntry(date: day(-9 + i, from: now), page: (i + 1) * 20) }
        b.currentPage = 200
        let f = ReadingForecast.make(book: b, sessions: [], now: now, calendar: cal)
        #expect(f.confidence == .good)
        let pace = try #require(f.pagesPerDay)
        #expect(abs(pace - 20) < 0.01)
        #expect(f.finish == day(5, from: now))
        #expect(f.earliest! <= f.finish! && f.finish! <= f.latest!)
    }

    @Test func streaksCountConsecutiveDays() {
        let now = cal.startOfDay(for: Date())
        var days: [Date: Activity.Day] = [:]
        for i in [0, 1, 2, 5, 6] { days[day(-i, from: now)] = .init(pages: 10, seconds: 0, touched: true) }
        #expect(Activity.currentStreak(days, now: now, calendar: cal) == 3)
        #expect(Activity.longestStreak(days, calendar: cal) == 3)
    }
}
