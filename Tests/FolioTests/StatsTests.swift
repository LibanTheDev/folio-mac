import Foundation
import Testing
@testable import Folio

@Suite struct StatsTests {
    let cal = Calendar(identifier: .gregorian)

    func date(_ s: String) -> Date {
        let f = DateFormatter()
        f.calendar = cal
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f.date(from: s)!
    }

    @Test func importedHistoryCreatesNoActivityOrTime() throws {
        let csv = #"""
        Book Id,Title,Author,Author l-f,Additional Authors,ISBN,ISBN13,My Rating,Average Rating,Publisher,Binding,Number of Pages,Year Published,Original Publication Year,Date Read,Date Added,Bookshelves,Bookshelves with positions,Exclusive Shelf,My Review,Spoiler,Private Notes,Read Count,Owned Copies
        1,One,A,"A, A",,,,5,4,P,H,300,2026,2026,2026/02/01,2026/01/01,,,read,,,,1,0
        2,Two,B,"B, B",,,,0,4,P,H,250,2026,2026,,2026/01/01,currently-reading,,currently-reading,,,,0,0
        """#
        let books = try GoodreadsCSV.parse(csv)
        let stats = YearStats.make(year: 2026, books: books, sessions: [], calendar: cal)
        #expect(stats.booksCompleted == 1)
        #expect(stats.pagesRead == 300)  // the finished book only
        #expect(stats.secondsRead == 0)
        #expect(stats.sessionCount == 0)
        #expect(stats.readingDays == 0)
        #expect(Activity.daily(books: books, sessions: [], calendar: cal).isEmpty)
    }

    @Test func loggedProgressAndSessionsCount() {
        var b = Book(title: "Live", authors: [], pageCount: 400)
        b.status = .reading
        b.dateStarted = date("2026-03-01 09:00")
        b.progressLog = [ProgressEntry(date: date("2026-03-01 21:00"), page: 40),
                         ProgressEntry(date: date("2026-03-02 21:00"), page: 90)]
        b.currentPage = 90
        let session = ReadingSession(bookID: b.id, start: date("2026-03-03 20:00"), duration: 1800, startPage: 90, endPage: 120)
        let stats = YearStats.make(year: 2026, books: [b], sessions: [session], calendar: cal)
        #expect(stats.pagesRead == 120)
        #expect(stats.secondsRead == 1800)
        #expect(stats.readingDays == 3)
    }

    @MainActor @Test func sessionLifecycleRecordsActiveTimeOnly() throws {
        let lib = Library(directory: FileManager.default.temporaryDirectory.appendingPathComponent("folio-s-\(UUID())"), autosave: false)
        var b = Book(title: "S", authors: [], pageCount: 300)
        b.status = .reading
        b.currentPage = 50
        lib.books = [b]
        let t0 = Date(timeIntervalSince1970: 1_000_000)
        lib.startSession(b.id, at: t0)
        lib.pauseSession(at: t0.addingTimeInterval(600))
        lib.resumeSession(at: t0.addingTimeInterval(1_800))      // 20 min paused
        let s = try #require(lib.finishSession(endPage: 80, at: t0.addingTimeInterval(2_400)))
        #expect(s.duration == 1_200)
        #expect(s.pagesRead == 30)
        #expect(lib.book(b.id)?.currentPage == 80)
        #expect(lib.activeSession == nil)
        // Accidental taps are not recorded.
        lib.startSession(b.id, at: t0)
        #expect(lib.finishSession(endPage: nil, at: t0.addingTimeInterval(3)) == nil)
        #expect(lib.sessions.count == 1)
    }
}

@Suite struct ActivitySpreadTests {
    @Test func firstUpdateIsSpreadSinceStart() {
        let cal = Calendar(identifier: .gregorian)
        let start = cal.startOfDay(for: Date(timeIntervalSince1970: 1_800_000_000))
        var b = Book(title: "X", authors: [], pageCount: 500)
        b.status = .reading
        b.dateStarted = start
        b.progressLog = [ProgressEntry(date: cal.date(byAdding: .day, value: 4, to: start)!, page: 100)]
        let days = Activity.daily(books: [b], sessions: [], calendar: cal)
        #expect(days.values.reduce(0) { $0 + $1.pages } == 100)
        #expect(days.count == 5)
        #expect(days.values.filter(\.touched).count == 1)  // only the day of the update counts as recorded
    }
}
