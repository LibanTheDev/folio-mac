import Foundation

/// A search result that always points back to its source.
struct SearchHit: Identifiable, Hashable {
    enum Source: Hashable {
        case book(UUID)
        case note(noteID: UUID, bookID: UUID)
    }

    enum Field: String, Hashable {
        case title = "Title", author = "Author", tag = "Tag", note = "Note", synopsis = "Description", review = "Review", meaning = "Related meaning"
    }

    let source: Source
    let title: String
    let subtitle: String
    let snippet: String
    let field: Field
    var score: Double
    var noteKind: BookNote.Kind?

    var id: String {
        switch source {
        case .book(let id): "b-\(id.uuidString)"
        case .note(let n, _): "n-\(n.uuidString)"
        }
    }

    var bookID: UUID {
        switch source {
        case .book(let id): id
        case .note(_, let b): b
        }
    }
}

/// Keyword search across books and personal knowledge.
enum KeywordSearch {
    static let stopWords: Set<String> = [
        "a", "an", "and", "are", "as", "at", "be", "but", "by", "do", "for", "from", "has", "have", "how", "i", "in",
        "is", "it", "its", "me", "my", "of", "on", "or", "over", "so", "than", "that", "the", "their", "them", "there",
        "they", "this", "to", "up", "was", "we", "what", "when", "which", "who", "why", "with", "you", "your", "many",
        "much", "some", "very", "about", "into", "out", "just", "can", "will", "would", "should", "could", "did", "does",
        "years", "year", "time", "things", "thing", "get", "getting", "got", "make", "made", "more", "most", "all",
        "learn", "learned", "learnt", "learning", "know", "knew", "think", "said", "say", "says", "tell", "notes", "note",
    ]

    static func tokens(_ s: String) -> [String] {
        let words = s.lowercased()
            .folding(options: .diacriticInsensitive, locale: .current)
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count >= 2 }
        let meaningful = words.filter { !stopWords.contains($0) }
        // A query made only of common words still searches for them.
        return meaningful.isEmpty ? words : meaningful
    }

    /// Fraction of query tokens present (prefix match), weighted to favour phrase matches.
    static func score(_ text: String, query: String, tokens q: [String], minCoverage: Double = 0.5) -> Double {
        guard !q.isEmpty, !text.isEmpty else { return 0 }
        let lowered = text.lowercased().folding(options: .diacriticInsensitive, locale: .current)
        let words = Set(tokens(lowered))
        let hits = q.filter { t in lowered.contains(t) && (words.contains(t) || words.contains { $0.hasPrefix(t) }) }.count
        // Longer queries need at least half their meaningful words present.
        guard hits > 0, q.count <= 2 || Double(hits) / Double(q.count) >= minCoverage else { return 0 }
        var s = Double(hits) / Double(q.count)
        if lowered.contains(query.lowercased()) { s += 0.5 }
        return s
    }

    /// Excerpt of `text` around the first matching token.
    static func snippet(_ text: String, tokens q: [String], radius: Int = 70) -> String {
        let flat = text.replacingOccurrences(of: "\n", with: " ")
        let lowered = flat.lowercased()
        guard let first = q.compactMap({ lowered.range(of: $0) }).min(by: { $0.lowerBound < $1.lowerBound }) else {
            return String(flat.prefix(radius * 2))
        }
        let start = flat.index(first.lowerBound, offsetBy: -radius, limitedBy: flat.startIndex) ?? flat.startIndex
        let end = flat.index(first.upperBound, offsetBy: radius, limitedBy: flat.endIndex) ?? flat.endIndex
        return (start > flat.startIndex ? "…" : "") + flat[start..<end].trimmingCharacters(in: .whitespaces) + (end < flat.endIndex ? "…" : "")
    }

    static func search(_ query: String, books: [Book], limit: Int = 60, minCoverage: Double = 0.5) -> [SearchHit] {
        let q = tokens(query)
        guard !q.isEmpty else { return [] }
        var hits: [SearchHit] = []
        for b in books {
            var best: (Double, SearchHit.Field, String)?
            func consider2(_ text: String, _ field: SearchHit.Field, weight: Double) {
                let s = score(text, query: query, tokens: q, minCoverage: minCoverage) * weight
                if s > 0, s > (best?.0 ?? 0) { best = (s, field, text) }
            }
            consider2(b.title, .title, weight: 3)
            consider2(b.authors.joined(separator: ", "), .author, weight: 2.5)
            consider2(b.tags.joined(separator: " "), .tag, weight: 2)
            consider2(b.synopsis ?? "", .synopsis, weight: 0.8)
            consider2(b.review, .review, weight: 1.2)
            if let (s, field, text) = best {
                let snippet = field == .title || field == .author ? b.authorLine : snippet(text, tokens: q)
                hits.append(SearchHit(source: .book(b.id), title: b.title, subtitle: b.authorLine, snippet: snippet, field: field, score: s))
            }
            for n in b.notes {
                // The note's own book and author are part of its context ("my notes on Atomic Habits").
                let parts: [String] = [n.plainText, n.tags.joined(separator: " "), n.chapter ?? "", b.title, b.authorLine]
                let text = parts.joined(separator: " ")
                let s = score(text, query: query, tokens: q, minCoverage: minCoverage) * 1.6
                if s > 0 {
                    hits.append(SearchHit(source: .note(noteID: n.id, bookID: b.id), title: b.title,
                                          subtitle: [n.kind.title, n.locationLabel].compactMap { $0 }.joined(separator: " · "),
                                          snippet: snippet(n.plainText, tokens: q), field: .note, score: s, noteKind: n.kind))
                }
            }
        }
        return Array(hits.sorted { $0.score > $1.score }.prefix(limit))
    }
}
