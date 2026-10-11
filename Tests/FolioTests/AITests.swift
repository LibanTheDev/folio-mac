import Foundation
import Testing
@testable import Folio

@Suite struct AIProviderTests {
    @Test func anthropicRequestUsesStructuredOutputAndFallbacks() throws {
        let p = AnthropicProvider(apiKey: "k")
        let body = p.body(for: AIRequest(system: "s", user: "u", schema: ["type": "object"]))
        #expect(body["model"] as? String == "claude-opus-5-5")
        #expect(body["fallbacks"] as? String == "default")
        let config = try #require(body["output_config"] as? [String: Any])
        #expect((config["format"] as? [String: Any])?["type"] as? String == "json_schema")
        #expect(body["thinking"] == nil)  // Opus 5.5 always thinks adaptively; never send disabled/budget
    }

    @Test func anthropicParseHandlesStopReasons() throws {
        let ok: [String: Any] = ["stop_reason": "end_turn", "model": "claude-opus-5-5",
                                 "content": [["type": "thinking", "thinking": ""], ["type": "text", "text": "{\"ok\": true}"]]]
        let r = try AnthropicProvider.parse(ok)
        #expect(String(decoding: r.json, as: UTF8.self) == "{\"ok\": true}")
        #expect(throws: AIError.self) { try AnthropicProvider.parse(["stop_reason": "refusal", "stop_details": ["category": "cyber"], "content": []]) }
        #expect(throws: AIError.self) { try AnthropicProvider.parse(["stop_reason": "max_tokens", "content": []]) }
    }

    @Test func jsonExtractionToleratesFencesAndBraces() {
        let text = "Here you go:\n```json\n{\"a\": \"x } y\", \"b\": {\"c\": 1}}\n```"
        let data = JSONExtraction.object(in: text)
        #expect(data.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }?["a"] as? String == "x } y")
        #expect(JSONExtraction.object(in: "no json here") == nil)
    }
}

@Suite struct DiscoveryTests {
    func doc(_ key: String, _ title: String, _ authors: [String]) -> OLDoc {
        OLDoc(key: key, title: title, author_name: authors, first_publish_year: 2000, cover_i: 1, number_of_pages_median: 300,
              isbn: nil, subject: nil, publisher: nil, ratings_average: nil, ratings_count: nil)
    }

    @Test func matcherHandlesSubtitlesArticlesAndSurnames() {
        #expect(BookMatcher.titlesMatch("The Outsiders: Eight Unconventional CEOs", "Outsiders"))
        #expect(BookMatcher.titlesMatch("Poor Charlie's Almanack", "Poor Charlies Almanack"))
        #expect(!BookMatcher.titlesMatch("The Outsiders", "The Insiders Guide"))
        #expect(BookMatcher.authorsMatch(claimed: "William N. Thorndike", actual: ["William Thorndike Jr."]))
        #expect(!BookMatcher.authorsMatch(claimed: "Jane Doe", actual: ["John Smith"]))
    }

    @Test func verificationDropsInventedLibraryAndDismissedBooks() async {
        let catalogue: [String: OLDoc] = [
            "Shoe Dog": doc("/works/OL1W", "Shoe Dog", ["Phil Knight"]),
            "The Outsiders": doc("/works/OL2W", "The Outsiders", ["William Thorndike"]),
            "Made in Japan": doc("/works/OL3W", "Made in Japan", ["Akio Morita"]),
        ]
        let candidates = [
            DiscoveryEngine.Candidate(title: "Shoe Dog", author: "Phil Knight", reason: "r1", related_library_titles: ["the outsiders"]),
            DiscoveryEngine.Candidate(title: "The Outsiders", author: "William Thorndike", reason: "r2", related_library_titles: []),
            DiscoveryEngine.Candidate(title: "A Book That Does Not Exist", author: "Nobody Real", reason: "r3", related_library_titles: []),
            DiscoveryEngine.Candidate(title: "Made in Japan", author: "Akio Morita", reason: "r4", related_library_titles: []),
            DiscoveryEngine.Candidate(title: "Shoe Dog", author: "Wrong Author", reason: "r5", related_library_titles: []),
        ]
        let owned = Book(title: "The Outsiders", authors: ["William Thorndike"])
        let out = await DiscoveryEngine.verify(candidates, books: [owned], dismissed: ["/works/OL3W"]) { title, _ in
            catalogue[title].map { [$0] } ?? []
        }
        #expect(out.recs.map(\.doc.title) == ["Shoe Dog"])
        #expect(out.recs.first?.relatedBookIDs == [owned.id])
        #expect(out.unverified.count == 2)       // invented title + wrong author
        #expect(out.skipped == 2)                // owned + dismissed
    }

    @Test func promptRespectsConsent() {
        var b = Book(title: "Secret Diary", authors: ["Me"])
        b.rating = 5
        let without = DiscoveryEngine.prompt(query: "q", books: [b], interests: [], dismissed: [], shareLibrary: false, notes: [])
        #expect(!without.contains("Secret Diary"))
        let with = DiscoveryEngine.prompt(query: "q", books: [b], interests: ["chess"], dismissed: [], shareLibrary: true, notes: [])
        #expect(with.contains("Secret Diary"))
        #expect(with.contains("chess"))
    }

    struct MockProvider: AIProvider {
        let json: String
        var displayName: String { "Mock" }
        func complete(_ request: AIRequest) async throws -> AIResponse { AIResponse(json: Data(json.utf8), model: "mock") }
    }

    @Test func invalidModelOutputIsReported() async {
        await #expect(throws: AIError.self) {
            _ = try await DiscoveryEngine.run(query: "q", provider: MockProvider(json: "{\"nope\": 1}"), books: [], interests: [],
                                              dismissed: [], shareLibrary: false, notes: [])
        }
    }
}

@Suite struct KeychainTests {
    @Test func roundTripsAndDeletes() throws {
        let account = "folio-test-\(UUID().uuidString)"
        defer { Keychain.delete(account: account) }
        #expect(Keychain.get(account: account) == nil)
        try Keychain.set("secret-1", account: account)
        #expect(Keychain.get(account: account) == "secret-1")
        try Keychain.set("secret-2", account: account)   // update path
        #expect(Keychain.get(account: account) == "secret-2")
        Keychain.delete(account: account)
        #expect(Keychain.get(account: account) == nil)
    }
}
