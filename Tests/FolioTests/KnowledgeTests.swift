import Foundation
import Testing
@testable import Folio

@MainActor @Suite struct KnowledgeTests {
    func library() -> Library {
        let lib = Library(directory: FileManager.default.temporaryDirectory.appendingPathComponent("folio-k-\(UUID())"), autosave: false)
        var a = Book(title: "The Outsiders", authors: ["William Thorndike"])
        a.notes = [BookNote(kind: .lesson, text: "Great CEOs treat **capital allocation** as their most important job.", tags: ["capital-allocation"]),
                   BookNote(kind: .mentalModel, text: "Decentralize operations, centralize capital decisions.")]
        var b = Book(title: "Poor Charlie's Almanack", authors: ["Charles Munger"])
        b.notes = [BookNote(kind: .reflection, text: "Incentives drive behaviour more than intentions do.", page: 42, chapter: "Psychology")]
        lib.books = [a, b]
        return lib
    }

    @Test func keywordSearchFindsNotesAndBooksWithSnippets() {
        let lib = library()
        let hits = KeywordSearch.search("capital allocation", books: lib.books)
        let note = hits.first { $0.field == .note }
        #expect(note != nil)
        #expect(note?.snippet.contains("capital allocation") == true)
        #expect(KeywordSearch.search("munger", books: lib.books).first?.field == .author)
        #expect(KeywordSearch.search("psychology", books: lib.books).count == 1)  // chapter is searchable
        #expect(KeywordSearch.search("zzzz", books: lib.books).isEmpty)
        // Filler words alone don't produce matches on long queries.
        #expect(KeywordSearch.search("getting better slowly over many years", books: lib.books).isEmpty)
    }

    @Test func linksAreBidirectionalAndCleanedUp() throws {
        let lib = library()
        let a = lib.books[0].notes[0].id
        let b = lib.books[1].notes[0].id
        lib.link(a, to: b)
        #expect(lib.connections(of: a).map(\.note.id) == [b])
        #expect(lib.connections(of: b).map(\.note.id) == [a])  // backlink
        lib.unlink(b, a)
        #expect(lib.connections(of: a).isEmpty)
        lib.link(a, to: b)
        lib.deleteNote(b)
        #expect(lib.note(a)?.note.links.isEmpty == true)
    }

    @Test func updateNoteBumpsTimestampOnlyOnChange() throws {
        let lib = library()
        let id = lib.books[0].notes[0].id
        let before = try #require(lib.note(id)).note.updated
        lib.updateNote(id) { _ in }
        #expect(lib.note(id)?.note.updated == before)
        lib.updateNote(id) { $0.text += " Edited." }
        #expect(lib.note(id)!.note.updated > before)
    }

    @Test func plainTextStripsMarkdown() {
        #expect(BookNote(text: "**Bold** and _italic_ with `code`").plainText == "Bold and italic with code")
    }

    @Test func semanticSearchFindsMeaningWithoutSharedWords() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("folio-emb-\(UUID())")
        let index = EmbeddingIndex(cacheDirectory: dir)
        try #require(index.isAvailable, "On-device sentence embeddings unavailable on this machine")
        let lib = library()
        let results = index.semanticNotes("rewards and motivation shape how people act", books: lib.books, threshold: 0.3)
        #expect(results.first?.0.note.text.contains("Incentives") == true)
        // Cache is persisted for reuse.
        #expect(FileManager.default.fileExists(atPath: dir.appendingPathComponent("embeddings.json").path))
    }
}

@Suite struct CutoffTests {
    @Test func relativeCutoffSelectsStandouts() {
        let scores = [0.24, 0.16, 0.11, 0.11, 0.21]
        let cut = EmbeddingIndex.cutoff(scores, floor: 0.2, smallCorpus: 0.3)
        #expect(scores.filter { $0 >= cut } == [0.24, 0.21])  // the 0.16 and 0.11 noise is excluded
        #expect(EmbeddingIndex.cutoff([0.9, 0.1], floor: 0.2, smallCorpus: 0.3) == 0.3)
        #expect(EmbeddingIndex.cutoff([0.01, 0.02, 0.03, 0.02, 0.01], floor: 0.2, smallCorpus: 0.3) == 0.2)
    }
}
