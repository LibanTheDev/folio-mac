import Foundation
import Testing
@testable import Folio

@Suite struct AskFolioValidationTests {
    let sources = [
        AskFolio.Source(id: "S1", kind: .note(noteID: UUID(), bookID: UUID()), title: "The Outsiders", label: "Key Lesson",
                        text: "Great CEOs treat capital allocation as their most important job."),
        AskFolio.Source(id: "M1", kind: .metadata(bookID: UUID()), title: "The Outsiders", label: "Book information",
                        text: "The Outsiders by William Thorndike; published 2012"),
    ]

    func raw(_ json: String) throws -> AskFolio.RawAnswer {
        try JSONDecoder().decode(AskFolio.RawAnswer.self, from: Data(json.utf8))
    }

    @Test func validCitationsAndVerbatimQuotesPass() throws {
        let r = try raw(#"""
        {"insufficient_evidence": false, "sections": [
          {"kind": "from_your_notes", "paragraphs": [{"text": "You noted that CEOs treat \"capital allocation as their most important job\".", "citations": ["S1"]}]},
          {"kind": "from_book_metadata", "paragraphs": [{"text": "It was published in 2012.", "citations": ["[M1]"]}]}
        ]}
        """#)
        let v = AskFolio.validate(r, sources: sources)
        #expect(!v.insufficient)
        let p = v.sections[0].paragraphs[0]
        #expect(p.citations == ["S1"] && !p.unsupported && p.unverifiedQuotes.isEmpty)
        #expect(v.sections[1].paragraphs[0].citations == ["M1"])
    }

    @Test func fabricatedCitationsAndQuotesAreFlagged() throws {
        let r = try raw(#"""
        {"insufficient_evidence": false, "sections": [
          {"kind": "general_knowledge", "paragraphs": [{"text": "Conglomerates often diversify.", "citations": []}]},
          {"kind": "from_your_notes", "paragraphs": [{"text": "You wrote “incentives beat intentions every single time” in your notes.", "citations": ["S9"]}]}
        ]}
        """#)
        let v = AskFolio.validate(r, sources: sources)
        // Sections are ordered: notes, metadata, general knowledge.
        #expect(v.sections.map(\.kind) == [.from_your_notes, .general_knowledge])
        let p = v.sections[0].paragraphs[0]
        #expect(p.invalidCitations == ["S9"])
        #expect(p.unsupported)
        #expect(p.unverifiedQuotes.count == 1)
        #expect(v.insufficient)  // no supported note-based content
        #expect(!v.sections[1].paragraphs[0].unsupported)  // general knowledge needs no citation
    }

    @Test func promptListsSourcesAndHandlesNone() {
        let p = AskFolio.prompt(question: "Q?", mode: .themes, sources: sources)
        #expect(p.contains("[S1] (The Outsiders — Key Lesson)"))
        #expect(p.contains("recurring themes"))
        #expect(AskFolio.prompt(question: "Q?", mode: .ask, sources: []).contains("no saved notes"))
    }

    @MainActor @Test func retrievalIncludesNamedBookNotesAndMetadata() {
        var b = Book(title: "Poor Charlie's Almanack", authors: ["Charles Munger"])
        b.notes = [BookNote(kind: .reflection, text: "Incentives drive behaviour."), BookNote(kind: .lesson, text: "Invert, always invert.")]
        let other = Book(title: "Unrelated", authors: ["Someone"])
        let index = EmbeddingIndex(cacheDirectory: FileManager.default.temporaryDirectory.appendingPathComponent("folio-ask-\(UUID())"))
        let sources = AskFolio.retrieve("What did Munger teach me?", books: [b, other], index: index)
        #expect(sources.filter { $0.id.hasPrefix("S") }.count == 2)
        #expect(sources.contains { $0.id == "M1" && $0.text.contains("Poor Charlie's Almanack") })
    }
}

@Suite struct KnowledgeGraphTests {
    func library() -> [Book] {
        var a = Book(title: "A", authors: ["Ann Author"])
        a.tags = ["incentives"]
        var n1 = BookNote(kind: .mentalModel, text: "Second-order thinking", tags: ["decisions"])
        var b = Book(title: "B", authors: ["Bob Writer"])
        b.tags = ["incentives"]
        let n2 = BookNote(kind: .reflection, text: "Think about consequences of consequences", tags: ["decisions"])
        n1.links = [n2.id]
        a.notes = [n1]
        b.notes = [n2]
        var lonely = Book(title: "C", authors: ["Cy"])
        lonely.tags = ["unique-tag"]
        return [a, b, lonely]
    }

    @Test func buildsTraceableEdgesAndDropsSingletonConcepts() {
        let g = KnowledgeGraph.build(books: library(), includeNotes: true)
        #expect(g.node(KnowledgeGraph.conceptID("incentives")) != nil)
        #expect(g.node(KnowledgeGraph.conceptID("decisions")) != nil)
        #expect(g.node(KnowledgeGraph.conceptID("unique-tag")) == nil)   // connects only one thing
        #expect(g.nodes.contains { $0.kind == .mentalModel })
        #expect(g.edges.contains { $0.reason == "connected notes" })
        #expect(g.edges.allSatisfy { !$0.reason.isEmpty })
        let neighbors = g.neighbors(of: KnowledgeGraph.conceptID("incentives")).map(\.node.label).sorted()
        #expect(neighbors == ["A", "B"])
    }

    @Test func focusLimitsToNeighborhoodAndLayoutIsDeterministic() {
        var g1 = KnowledgeGraph.build(books: library(), includeNotes: false, focus: KnowledgeGraph.conceptID("incentives"))
        #expect(Set(g1.nodes.map(\.label)) == ["Incentives", "A", "B", "Ann Author", "Bob Writer"])
        var g2 = g1
        g1.layout(); g2.layout()
        #expect(g1.positions == g2.positions)
        #expect(g1.positions.values.allSatisfy { abs($0.x) <= 0.5001 && abs($0.y) <= 0.5001 })
    }
}

@MainActor @Suite struct AskRetrievalTests {
    @Test func questionRetrievesNotesViaBookTitleAndTags() {
        var habits = Book(title: "Atomic Habits", authors: ["James Clear"])
        habits.notes = [BookNote(kind: .mentalModel, text: "Systems beat goals: design the environment.", tags: ["systems"]),
                        BookNote(kind: .lesson, text: "Small improvements compound.", tags: ["compounding", "habits"])]
        var other = Book(title: "Sapiens", authors: ["Yuval Noah Harari"])
        other.notes = [BookNote(kind: .question, text: "If institutions are shared fictions, what makes some last?")]
        let index = EmbeddingIndex(cacheDirectory: FileManager.default.temporaryDirectory.appendingPathComponent("folio-ask2-\(UUID())"))
        let sources = AskFolio.retrieve("What have I learned about building systems and habits?", books: [other, habits], index: index)
        let notes = sources.filter { $0.id.hasPrefix("S") }
        #expect(notes.prefix(2).allSatisfy { $0.title == "Atomic Habits" })
    }
}
