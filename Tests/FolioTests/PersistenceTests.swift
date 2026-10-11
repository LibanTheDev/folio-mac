import Foundation
import Testing
@testable import Folio

@Suite struct PersistenceTests {
    func tempDir() -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("folio-tests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func fixture() throws -> Data {
        let url = try #require(Bundle.module.url(forResource: "library-v1", withExtension: "json", subdirectory: "Fixtures"))
        return try Data(contentsOf: url)
    }

    @Test func decodesV1FileWithAllBooks() throws {
        let file = try LibraryStore.decode(fixture())
        #expect(file.books.count == 15)
        #expect(file.goals[2026] == 20)
        let hail = try #require(file.books.first { $0.title == "Project Hail Mary" })
        #expect(hail.status == .reading)
        #expect(hail.currentPage == 212)
        #expect(hail.history.isEmpty)
        #expect(hail.queueRank == nil)
    }

    @MainActor @Test func migratesV1AndBacksUpOriginal() throws {
        let dir = tempDir()
        try fixture().write(to: dir.appendingPathComponent("library.json"))
        let library = Library(directory: dir, autosave: false)
        #expect(library.books.count == 15)
        let backups = try FileManager.default.contentsOfDirectory(atPath: dir.appendingPathComponent("Backups").path)
        #expect(backups.contains { $0.contains("pre-migration-v1") })
        // The migrated file is written in the current schema.
        let json = try JSONSerialization.jsonObject(with: Data(contentsOf: dir.appendingPathComponent("library.json"))) as? [String: Any]
        #expect(json?["version"] as? Int == LibraryFile.currentVersion)
    }

    @Test func toleratesMissingAndMalformedFields() throws {
        let json = #"""
        {"version": 2, "books": [
          {"title": "Bare"},
          {"title": "Odd", "rating": "five", "status": "unknown-status", "notes": [{"text": "hi", "isQuote": true}]}
        ]}
        """#
        let file = try LibraryStore.decode(Data(json.utf8))
        #expect(file.books.count == 2)
        #expect(file.books[0].status == .wantToRead)
        #expect(file.books[1].rating == nil)
        #expect(file.books[1].status == .wantToRead)
        #expect(file.books[1].notes.first?.kind == .quote)
    }

    @MainActor @Test func unreadableFileIsNeverOverwritten() throws {
        let dir = tempDir()
        let garbage = Data("{ not json".utf8)
        try garbage.write(to: dir.appendingPathComponent("library.json"))
        let library = Library(directory: dir, autosave: false)
        #expect(library.loadError != nil)
        library.books.append(Book(title: "New", authors: []))
        library.save()
        #expect(try Data(contentsOf: dir.appendingPathComponent("library.json")) == garbage)
    }

    @Test func roundTripsCurrentSchema() throws {
        var file = LibraryFile()
        var b = Book(title: "A", authors: ["X"])
        // Millisecond precision is what the file format keeps.
        b.dateAdded = Date(timeIntervalSince1970: 1_700_000_000.125)
        b.updatedAt = Date(timeIntervalSince1970: 1_700_000_100.5)
        b.history = [ReadThrough(started: Date(timeIntervalSince1970: 0), finished: Date(timeIntervalSince1970: 86_400), rating: 4)]
        b.notes = [BookNote(created: Date(timeIntervalSince1970: 1_700_000_200), kind: .mentalModel, text: "**Flywheel**",
                            page: 12, chapter: "3", tags: ["growth"])]
        file.books = [b]
        file.shelves = [Shelf(name: "S", kind: .smart, rules: [ShelfRule(.rating, .atLeast, "4")])]
        file.sessions = [ReadingSession(bookID: b.id, start: Date(timeIntervalSince1970: 100), duration: 600, startPage: 1, endPage: 20)]
        let data = try LibraryStore.encoder().encode(file)
        let back = try LibraryStore.decode(data)
        #expect(back.books == file.books)
        #expect(back.shelves == file.shelves)
        #expect(back.sessions == file.sessions)
    }
}
