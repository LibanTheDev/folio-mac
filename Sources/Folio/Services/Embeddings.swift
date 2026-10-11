import CryptoKit
import Foundation
import NaturalLanguage

/// Local semantic index over notes and books using Apple's on-device sentence embeddings.
/// Nothing leaves the Mac. Vectors are cached on disk and are fully regenerable, so they're
/// never included in exports.
@MainActor
final class EmbeddingIndex: ObservableObject {
    static let shared = EmbeddingIndex()

    private struct Entry: Codable { let hash: String; let vector: [Float] }

    private let embedding = NLEmbedding.sentenceEmbedding(for: .english)
    private var cache: [String: Entry] = [:]
    private var dirty = false
    private let cacheURL: URL?

    var isAvailable: Bool { embedding != nil }

    init(cacheDirectory: URL? = nil) {
        let dir = cacheDirectory ?? FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Folio", isDirectory: true)
        if let dir {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            cacheURL = dir.appendingPathComponent("embeddings.json")
            if let data = try? Data(contentsOf: cacheURL!), let c = try? JSONDecoder().decode([String: Entry].self, from: data) {
                cache = c
            }
        } else {
            cacheURL = nil
        }
    }

    private static func hash(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8)).prefix(8).map { String(format: "%02x", $0) }.joined()
    }

    /// Embedding for arbitrary text, or nil when the model is unavailable.
    func vector(for text: String) -> [Float]? {
        guard let embedding else { return nil }
        let trimmed = String(text.prefix(1_500))
        return embedding.vector(for: trimmed)?.map(Float.init)
    }

    /// Cached embedding for an item, recomputed when its text changes.
    func vector(key: String, text: String) -> [Float]? {
        let h = Self.hash(text)
        if let e = cache[key], e.hash == h { return e.vector }
        guard let v = vector(for: text) else { return nil }
        cache[key] = Entry(hash: h, vector: v)
        dirty = true
        return v
    }

    func persist() {
        guard dirty, let cacheURL, let data = try? JSONEncoder().encode(cache) else { return }
        try? data.write(to: cacheURL, options: .atomic)
        dirty = false
    }

    nonisolated static func cosine(_ a: [Float], _ b: [Float]) -> Double {
        guard a.count == b.count, !a.isEmpty else { return 0 }
        var dot: Float = 0, na: Float = 0, nb: Float = 0
        for i in a.indices { dot += a[i] * b[i]; na += a[i] * a[i]; nb += b[i] * b[i] }
        guard na > 0, nb > 0 else { return 0 }
        return Double(dot / (na.squareRoot() * nb.squareRoot()))
    }

    static func noteText(_ n: BookNote, book: Book) -> String {
        [n.plainText, n.tags.joined(separator: " "), n.chapter ?? ""].joined(separator: " ")
    }

    /// Picks the scores that stand out from the rest. Absolute cosine values from the on-device
    /// model vary a lot with query length, so the cutoff is relative (mean + 0.8 SD) with an
    /// absolute floor. Small corpora fall back to a fixed threshold.
    nonisolated static func cutoff(_ scores: [Double], floor: Double, smallCorpus: Double) -> Double {
        guard scores.count >= 5 else { return smallCorpus }
        let mean = scores.reduce(0, +) / Double(scores.count)
        let sd = (scores.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Double(scores.count)).squareRoot()
        return max(floor, mean + 0.8 * sd)
    }

    /// Notes ranked by meaning similarity to `query`.
    func semanticNotes(_ query: String, books: [Book], threshold: Double? = nil, limit: Int = 12) -> [(NoteRef, Double)] {
        guard let qv = vector(for: query) else { return [] }
        var all: [(NoteRef, Double)] = []
        for b in books {
            for n in b.notes {
                guard let v = vector(key: "n:\(n.id.uuidString)", text: Self.noteText(n, book: b)) else { continue }
                all.append((NoteRef(note: n, book: b), Self.cosine(qv, v)))
            }
        }
        persist()
        let cut = threshold ?? Self.cutoff(all.map(\.1), floor: 0.2, smallCorpus: 0.3)
        return Array(all.filter { $0.1 >= cut }.sorted { $0.1 > $1.1 }.prefix(limit))
    }

    /// Notes in other books that mean something similar to `note`.
    func similarNotes(to note: BookNote, in book: Book, books: [Book], limit: Int = 5) -> [(NoteRef, Double)] {
        guard let v = vector(key: "n:\(note.id.uuidString)", text: Self.noteText(note, book: book)) else { return [] }
        var all: [(NoteRef, Double)] = []
        for b in books where b.id != book.id {
            for n in b.notes {
                guard let w = vector(key: "n:\(n.id.uuidString)", text: Self.noteText(n, book: b)) else { continue }
                all.append((NoteRef(note: n, book: b), Self.cosine(v, w)))
            }
        }
        persist()
        let cut = Self.cutoff(all.map(\.1), floor: 0.32, smallCorpus: 0.4)
        return Array(all.filter { $0.1 >= cut && !note.links.contains($0.0.note.id) && !$0.0.note.links.contains(note.id) }
            .sorted { $0.1 > $1.1 }.prefix(limit))
    }

    /// Hybrid search: keyword hits, plus notes that match by meaning but share no keywords.
    func hybridSearch(_ query: String, books: [Book], limit: Int = 60) -> [SearchHit] {
        var hits = KeywordSearch.search(query, books: books, limit: limit)
        let seen = Set(hits.map(\.id))
        for (ref, s) in semanticNotes(query, books: books) {
            let id = "n-\(ref.note.id.uuidString)"
            if seen.contains(id) {
                if let i = hits.firstIndex(where: { $0.id == id }) { hits[i].score += s }
                continue
            }
            hits.append(SearchHit(source: .note(noteID: ref.note.id, bookID: ref.book.id), title: ref.book.title,
                                  subtitle: [ref.note.kind.title, ref.note.locationLabel].compactMap { $0 }.joined(separator: " · "),
                                  snippet: String(ref.note.plainText.prefix(160)), field: .meaning, score: s * 1.5,
                                  noteKind: ref.note.kind))
        }
        return Array(hits.sorted { $0.score > $1.score }.prefix(limit))
    }
}
