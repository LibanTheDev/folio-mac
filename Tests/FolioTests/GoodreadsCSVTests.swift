import Foundation
import Testing
@testable import Folio

@Suite struct GoodreadsCSVTests {
    let sample = #"""
    Book Id,Title,Author,Author l-f,Additional Authors,ISBN,ISBN13,My Rating,Average Rating,Publisher,Binding,Number of Pages,Year Published,Original Publication Year,Date Read,Date Added,Bookshelves,Bookshelves with positions,Exclusive Shelf,My Review,Spoiler,Private Notes,Read Count,Owned Copies
    2767052,"The Hunger Games (The Hunger Games, #1)",Suzanne Collins,"Collins, Suzanne",,"=""0439023483""","=""9780439023481""",4,4.31,Scholastic Press,Hardcover,374,2008,2008,2023/05/14,2023/04/01,"favorites, ya","favorites (#3), ya (#1)",read,"Loved it.<br/><br/>Second ""line"" here.",,my note,2,0
    5907,The Hobbit,J.R.R. Tolkien,"Tolkien, J.R.R.",,"=""""","=""""",0,4.29,Houghton,Paperback,366,2002,1937,,2024/01/02,currently-reading,currently-reading (#1),currently-reading,,,,0,0
    1,Some Slog,A Writer,"Writer, A",,,,0,3.1,X,Paperback,,2010,2010,,2024/02/02,did-not-finish,did-not-finish (#1),did-not-finish,,,,0,0
    """#

    @Test func parsesStatusesRatingsAndFields() throws {
        let books = try GoodreadsCSV.parse(sample)
        #expect(books.count == 3)
        let hg = books[0]
        #expect(hg.title == "The Hunger Games (The Hunger Games, #1)")
        #expect(hg.isbn == "9780439023481")
        #expect(hg.status == .read)
        #expect(hg.rating == 4)
        #expect(hg.tags == ["favorites", "ya"])
        #expect(hg.review == "Loved it.\n\nSecond \"line\" here.")
        #expect(hg.readCount == 2)
        #expect(hg.notes.first?.text == "my note")
        #expect(hg.dateFinished != nil)
        #expect(books[1].status == .reading)
        #expect(books[1].isbn == nil)
        #expect(books[1].publishYear == 1937)
        #expect(books[2].status == .dnf)
    }

    @Test func rejectsNonGoodreadsFile() {
        #expect(throws: GoodreadsCSV.FormatError.self) { try GoodreadsCSV.parse("a,b\n1,2") }
    }

    @Test func exportRoundTrips() throws {
        let books = try GoodreadsCSV.parse(sample)
        let again = try GoodreadsCSV.parse(GoodreadsCSV.export(books))
        #expect(again.map(\.title) == books.map(\.title))
        #expect(again.map(\.status) == books.map(\.status))
        #expect(again[0].review == books[0].review)
    }
}

@MainActor @Suite struct GoodreadsIntegrityTests {
    @Test func importSurvivesSaveAndReload() throws {
        let csv = #"""
        Book Id,Title,Author,Author l-f,Additional Authors,ISBN,ISBN13,My Rating,Average Rating,Publisher,Binding,Number of Pages,Year Published,Original Publication Year,Date Read,Date Added,Bookshelves,Bookshelves with positions,Exclusive Shelf,My Review,Spoiler,Private Notes,Read Count,Owned Copies
        1,"Shoe Dog: A Memoir",Phil Knight,"Knight, Phil",,"=""1501135910""","=""9781501135910""",5,4.5,Scribner,Hardcover,386,2016,2016,2021/07/04,2021/06/01,"business, memoir",,read,"Loved the ""Blue Ribbon"" years.<br/>Second line.",,Re-read chapter 3,2,1
        2,Dune,Frank Herbert,"Herbert, Frank",,,"=""9780441172719""",0,4.3,Ace,Paperback,617,1990,1965,,2024/03/03,to-read,,to-read,,,,0,0
        """#
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("folio-gr-\(UUID())")
        let lib = Library(directory: dir, autosave: false)
        let summary = lib.merge(imported: try GoodreadsCSV.parse(csv))
        #expect(summary == .init(added: 2, updated: 0))
        lib.save()

        let reloaded = Library(directory: dir, autosave: false)
        #expect(reloaded.loadError == nil)
        #expect(reloaded.books.count == 2)
        let shoe = try #require(reloaded.books.first { $0.title == "Shoe Dog: A Memoir" })
        #expect(shoe.isbn == "9781501135910")
        #expect(shoe.rating == 5)
        #expect(shoe.status == .read)
        #expect(shoe.tags == ["business", "memoir"])
        #expect(shoe.review == "Loved the \"Blue Ribbon\" years.\nSecond line.")
        #expect(shoe.notes.map(\.text) == ["Re-read chapter 3"])
        #expect(shoe.readCount == 2)
        #expect(shoe.pageCount == 386 && shoe.currentPage == 386)
        let f = DateFormatter(); f.dateFormat = "yyyy/MM/dd"
        #expect(shoe.dateFinished == f.date(from: "2021/07/04"))
        #expect(shoe.dateAdded == f.date(from: "2021/06/01"))
        let dune = try #require(reloaded.books.first { $0.title == "Dune" })
        #expect(dune.status == .wantToRead && dune.rating == nil && dune.publishYear == 1965)
        // Imports never fabricate reading activity.
        #expect(reloaded.sessions.isEmpty)
        #expect(reloaded.books.allSatisfy { $0.progressLog.isEmpty })
    }
}
