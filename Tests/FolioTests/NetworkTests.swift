import Foundation
import Testing
@testable import Folio

/// Live Open Library checks. Run with FOLIO_NETWORK_TESTS=1 swift test.
@Suite(.enabled(if: ProcessInfo.processInfo.environment["FOLIO_NETWORK_TESTS"] == "1"))
struct NetworkTests {
    @Test func realBooksVerifyAndInventedOnesDont() async {
        let candidates = [
            DiscoveryEngine.Candidate(title: "The Outsiders: Eight Unconventional CEOs and Their Radically Rational Blueprint for Success",
                                      author: "William N. Thorndike", reason: "", related_library_titles: []),
            DiscoveryEngine.Candidate(title: "Shoe Dog", author: "Phil Knight", reason: "", related_library_titles: []),
            DiscoveryEngine.Candidate(title: "Made in Japan", author: "Akio Morita", reason: "", related_library_titles: []),
            DiscoveryEngine.Candidate(title: "The Snowball", author: "Alice Schroeder", reason: "", related_library_titles: []),
            DiscoveryEngine.Candidate(title: "The Copper Kings of Lower Zambezi", author: "Harriet Q. Invented", reason: "", related_library_titles: []),
        ]
        let out = await DiscoveryEngine.verify(candidates, books: [], dismissed: []) { title, author in
            (try? await OpenLibrary.searchTitleAuthor(title: title, author: author)) ?? []
        }
        #expect(out.recs.count == 4, "verified: \(out.recs.map(\.doc.title)), unverified: \(out.unverified)")
        #expect(out.unverified == ["The Copper Kings of Lower Zambezi — Harriet Q. Invented"])
    }
}
