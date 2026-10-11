import Foundation
import Testing
@testable import Folio

@Suite struct PerformanceTests {
    static func bigLibrary(_ n: Int) -> [Book] {
        let genres = ["Fantasy", "History", "Business", "Biography", "Science", "Poetry", "Investing"]
        return (0..<n).map { i in
            var b = Book(title: "Book \(i)", authors: ["Author \(i % 400)"], pageCount: 100 + (i * 37) % 900,
                         publishYear: 1900 + i % 125, subjects: [genres[i % genres.count], genres[(i + 3) % genres.count]])
            b.status = ReadingStatus.allCases[i % 4]
            b.rating = i % 3 == 0 ? nil : Double(i % 5 + 1)
            b.tags = i % 10 == 0 ? ["favourite-ish"] : []
            b.notes = (0..<(i % 4)).map { BookNote(kind: .highlight, text: "Note \($0) for book \(i) about compounding and incentives") }
            return b
        }
    }

    @Test func filteringAndSortingFiveThousandBooksIsFast() {
        let books = Self.bigLibrary(5_000)
        var filter = LibraryFilter()
        filter.genres = ["Business"]
        filter.minRating = 3
        let shelves = Shelf.templates(year: 2026)
        let clock = ContinuousClock()
        let elapsed = clock.measure {
            let out = books.filter { filter.matches($0, shelves: shelves) }.sorted(using: [SortKey.title.comparator])
            #expect(!out.isEmpty)
            for s in shelves { _ = books.filter { s.contains($0) } }
        }
        #expect(elapsed < .milliseconds(500), "took \(elapsed)")
    }

    @Test func encodingAndDecodingFiveThousandBooksIsFast() throws {
        var file = LibraryFile()
        file.books = Self.bigLibrary(5_000)
        let clock = ContinuousClock()
        var data = Data()
        let enc = try clock.measure { data = try LibraryStore.encoder().encode(file) }
        let dec = try clock.measure { _ = try LibraryStore.decode(data) }
        #expect(enc < .seconds(2), "encode took \(enc)")
        #expect(dec < .seconds(2), "decode took \(dec)")
    }
}
