import Foundation
import Testing
import UserNotifications
@testable import Folio

@Suite struct ExportTests {
    func book() -> Book {
        var b = Book(title: "Poor Charlie's Almanack: The Wit", authors: ["Charles Munger"], isbn: "978/1")
        b.status = .read
        b.rating = 4.5
        b.review = "Dense but **worth it**."
        b.tags = ["investing"]
        let other = BookNote(kind: .lesson, text: "Invert, always invert.", page: 10)
        var q = BookNote(kind: .quote, text: "A quoted line\nspanning two lines", page: 3, chapter: "Talk 2", tags: ["wisdom"])
        q.links = [other.id]
        b.notes = [other, q]
        return b
    }

    @Test func markdownHasFrontMatterGroupsAndLinks() {
        let b = book()
        let md = MarkdownExporter.markdown(for: b) { $0 == b.notes[0].id ? "Linked Book" : nil }
        #expect(md.hasPrefix("---\ntitle: \"Poor Charlie's Almanack: The Wit\""))
        #expect(md.contains("rating: 4.5"))
        #expect(md.contains("## My Review"))
        #expect(md.contains("## Quotes\n\n> A quoted line\n> spanning two lines"))
        #expect(md.contains("Talk 2 · p. 3 · #wisdom · Connected to: [[Linked Book]]"))
        #expect(md.range(of: "## Quotes")!.lowerBound < md.range(of: "## Key Lessons")!.lowerBound)
        #expect(MarkdownExporter.filename(for: b) == "Poor Charlie's Almanack- The Wit - Charles Munger.md")
    }

    @Test func sessionsCSVEscapesAndComputesPages() {
        let b = Book(title: "Comma, Book", authors: ["A"])
        let s = ReadingSession(bookID: b.id, start: Date(timeIntervalSince1970: 0), duration: 1_800, startPage: 10, endPage: 40)
        let csv = SessionsCSV.export([s], books: [b])
        #expect(csv.split(separator: "\n")[1].hasPrefix("\"Comma, Book\",A,1970-01-01T00:00:00Z,30.0,10,40,30,no"))
    }

    @Test func cloudBackupWritesDailyAndPrunes() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("folio-cloud-\(UUID())")
        let day: (Int) -> Date = { Date(timeIntervalSince1970: Double($0) * 86_400) }
        for i in 0..<5 { _ = try CloudBackup.backup(Data("{}".utf8), keep: 3, now: day(i), to: dir) }
        let files = try FileManager.default.contentsOfDirectory(atPath: dir.path).sorted()
        #expect(files.count == 3)
        #expect(files.last == "Folio 1970-01-05.folio.json")
    }
}

@Suite struct ReminderTests {
    @Test func triggersOnePerWeekdayAtTime() {
        let t = Reminders.triggers(hour: 21, minute: 30, weekdays: [2, 4, 6])
        #expect(t.map(\.0) == ["folio.reminder.2", "folio.reminder.4", "folio.reminder.6"])
        #expect(t.allSatisfy { $0.1.repeats && $0.1.dateComponents.hour == 21 && $0.1.dateComponents.minute == 30 })
    }

    @Test func messageUsesStreakAndCurrentBook() {
        let m = Reminders.message(currentlyReading: ["Dune", "Circe"], streak: 4)
        #expect(m.title == "Keep your 4-day streak going")
        #expect(m.body == "Pick up Dune or Circe for a few pages.")
        #expect(Reminders.message(currentlyReading: ["A", "B", "C"], streak: 0).body == "Pick up A or one of your 2 other books.")
        #expect(Reminders.message(currentlyReading: [], streak: 0).title == "Time to read")
    }
}

@Suite struct DragTests {
    @Test func dragPayloadRoundTripsAndExportsReadableText() throws {
        let b = Book(title: "Dune", authors: ["Frank Herbert"])
        let drag = FolioDrag.book(b)
        let data = try JSONEncoder().encode(drag)
        #expect(try JSONDecoder().decode(FolioDrag.self, from: data) == drag)
        #expect(drag.plainText == "Dune by Frank Herbert")
    }
}

@MainActor @Suite struct RestoreTests {
    @Test func restoreBacksUpCurrentLibraryFirst() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("folio-restore-\(UUID())")
        let lib = Library(directory: dir, autosave: false)
        lib.books = [Book(title: "Current", authors: [])]
        lib.save()
        var file = LibraryFile()
        file.books = [Book(title: "From Backup", authors: [])]
        lib.restore(from: file)
        #expect(lib.books.map(\.title) == ["From Backup"])
        let backups = try FileManager.default.contentsOfDirectory(atPath: lib.store.backupsURL.path)
        let safety = try #require(backups.first { $0.contains("before-restore") })
        let saved = try LibraryStore.decode(Data(contentsOf: lib.store.backupsURL.appendingPathComponent(safety)))
        #expect(saved.books.map(\.title) == ["Current"])
    }
}
