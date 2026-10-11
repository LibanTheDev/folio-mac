import Foundation
import Testing
@testable import Folio

/// End-to-end checks against the real Anthropic API. Opt-in: FOLIO_ANTHROPIC_KEY=… swift test --filter LiveAITests
/// Costs a few cents per run. The key is read from the environment only and never stored.
@Suite(.enabled(if: ProcessInfo.processInfo.environment["FOLIO_ANTHROPIC_KEY"] != nil), .serialized)
struct LiveAITests {
    var provider: AnthropicProvider {
        AnthropicProvider(apiKey: ProcessInfo.processInfo.environment["FOLIO_ANTHROPIC_KEY"]!)
    }

    @Test func connectionReturnsSchemaJSON() async throws {
        let r = try await provider.complete(AIRequest(
            system: "You are a connectivity check.", user: "Reply with ok set to true.",
            schema: ["type": "object", "properties": ["ok": ["type": "boolean"]], "required": ["ok"], "additionalProperties": false],
            maxTokens: 2_000))
        let obj = try JSONSerialization.jsonObject(with: r.json) as? [String: Any]
        #expect(obj?["ok"] as? Bool == true)
        print("LIVE model:", r.model)
    }

    @Test func discoveryReturnsVerifiedBooks() async throws {
        var outsiders = Book(title: "The Outsiders", authors: ["William N. Thorndike"])
        outsiders.rating = 5
        let result = try await DiscoveryEngine.run(
            query: "Biographies of people who built industrial conglomerates in emerging markets",
            provider: provider, books: [outsiders], interests: ["capital allocation"], dismissed: [],
            shareLibrary: true, notes: [])
        print("LIVE verified:", result.recommendations.map { "\($0.doc.title) — \($0.doc.authorLine)" })
        print("LIVE unverified:", result.unverified, "skipped:", result.skippedKnown)
        #expect(result.recommendations.count >= 3)
        #expect(result.recommendations.allSatisfy { !$0.reason.isEmpty })
        #expect(!result.recommendations.contains { BookMatcher.titlesMatch($0.doc.title, "The Outsiders") })
    }

    @MainActor @Test func askFolioIsGroundedInNotes() async throws {
        var habits = Book(title: "Atomic Habits", authors: ["James Clear"])
        habits.notes = [BookNote(kind: .mentalModel, text: "Systems beat goals: design the environment so the good behaviour is the easy one.", tags: ["systems"]),
                        BookNote(kind: .lesson, text: "Small improvements compound: a 1% change repeated daily matters more than one big push.", tags: ["habits"])]
        var munger = Book(title: "Poor Charlie's Almanack", authors: ["Charles Munger"])
        munger.notes = [BookNote(kind: .reflection, text: "Incentives drive behaviour more than intentions do; design incentives first.", tags: ["incentives"])]
        let index = EmbeddingIndex(cacheDirectory: FileManager.default.temporaryDirectory.appendingPathComponent("folio-live-\(UUID())"))
        let answer = try await AskFolio.run(question: "What have I learned about shaping behaviour through systems and incentives?",
                                            mode: .ask, provider: provider, books: [habits, munger], index: index)
        for s in answer.sections {
            for p in s.paragraphs {
                print("LIVE [\(s.kind.rawValue)] cites=\(p.citations) invalid=\(p.invalidCitations) unverifiedQuotes=\(p.unverifiedQuotes) unsupported=\(p.unsupported)\n  \(p.text)")
            }
        }
        let notes = try #require(answer.sections.first { $0.kind == .from_your_notes })
        #expect(notes.paragraphs.contains { !$0.unsupported && $0.citations.contains { $0.hasPrefix("S") } })
        #expect(answer.sections.flatMap(\.paragraphs).allSatisfy { $0.invalidCitations.isEmpty && $0.unverifiedQuotes.isEmpty })
        #expect(!answer.insufficientEvidence)
    }
}
