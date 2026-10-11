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
