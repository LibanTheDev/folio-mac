import Foundation

/// Fuzzy matching between AI-provided bibliographic claims and real metadata.
enum BookMatcher {
    static func normalize(_ s: String) -> String {
        var t = s.lowercased().folding(options: .diacriticInsensitive, locale: .current)
        if let colon = t.firstIndex(where: { $0 == ":" || $0 == "(" }) { t = String(t[..<colon]) }  // drop subtitles/series
        t = t.replacingOccurrences(of: "&", with: "and")
            .replacingOccurrences(of: "'", with: "")
            .replacingOccurrences(of: "\u{2019}", with: "")
        t = t.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }.joined(separator: " ")
        for article in ["the ", "a ", "an "] where t.hasPrefix(article) { t = String(t.dropFirst(article.count)) }
        return t.trimmingCharacters(in: .whitespaces)
    }

    static func titlesMatch(_ a: String, _ b: String) -> Bool {
        let x = normalize(a), y = normalize(b)
        guard !x.isEmpty, !y.isEmpty else { return false }
        if x == y { return true }
        if min(x.count, y.count) >= 6, x.hasPrefix(y) || y.hasPrefix(x) { return true }
        let sx = Set(x.split(separator: " ")), sy = Set(y.split(separator: " "))
        let jaccard = Double(sx.intersection(sy).count) / Double(sx.union(sy).count)
        return jaccard >= 0.75
    }

    /// True when the claimed author's surname appears among the real authors.
    static func authorsMatch(claimed: String, actual: [String]) -> Bool {
        let tokens = normalize(claimed).split(separator: " ").map(String.init)
        guard let surname = tokens.last, surname.count >= 2 else { return false }
        return actual.contains { normalize($0).split(separator: " ").contains(Substring(surname)) }
    }
}

/// One AI suggestion after verification against Open Library.
struct Recommendation: Identifiable, Hashable {
    let doc: OLDoc
    /// AI-written explanation of why it fits (clearly labelled as AI in the UI).
    let reason: String
    /// Books from the user's own library the AI related this to (matched to real library entries).
    let relatedBookIDs: [UUID]
    var id: String { doc.key }
}

struct DiscoveryResult {
    var recommendations: [Recommendation]
    /// Suggestions dropped because they couldn't be matched to a real book.
    var unverified: [String]
    /// Suggestions dropped because they're already in the library or were dismissed.
    var skippedKnown: Int
    var provider: String
}

/// Conversational book discovery: the model proposes, Open Library verifies.
struct DiscoveryEngine {
    struct Candidate: Decodable {
        let title: String
        let author: String
        let reason: String
        let related_library_titles: [String]
    }

    struct Payload: Decodable { let recommendations: [Candidate] }

    static let schema: [String: Any] = [
        "type": "object",
        "properties": [
            "recommendations": [
                "type": "array",
                "items": [
                    "type": "object",
                    "properties": [
                        "title": ["type": "string"],
                        "author": ["type": "string"],
                        "reason": ["type": "string"],
                        "related_library_titles": ["type": "array", "items": ["type": "string"]],
                    ],
                    "required": ["title", "author", "reason", "related_library_titles"],
                    "additionalProperties": false,
                ],
            ],
        ],
        "required": ["recommendations"],
        "additionalProperties": false,
    ]

    static let system = """
    You are Folio's book discovery assistant. Recommend real, published books that answer the reader's request.

    Rules:
    - Only recommend books you are confident exist, with their exact published title and primary author. Every \
    suggestion is checked against a bibliographic database; unverifiable ones are discarded, so precision matters \
    more than quantity.
    - Never recommend a book listed under "Already in library" or "Dismissed".
    - "reason" is 1–2 sentences on why this book fits the request and, when relevant, this reader's taste. Refer \
    to the reader's books by title only if they appear in the context. Do not quote from books.
    - "related_library_titles" lists titles from the reader's library (exactly as written in the context) that \
    this book connects to; use an empty array if none.
    - Prefer a mix of well-known and overlooked titles when the request invites it.
    - Return 8 recommendations unless the request asks for a different number (maximum 12).
    """

    /// Builds the user prompt, including only the personal data the user has allowed.
    static func prompt(query: String, books: [Book], interests: [String], dismissed: [String],
                       shareLibrary: Bool, notes: [NoteRef]) -> String {
        var out = "Reader's request:\n\(query)\n"
        if shareLibrary {
            let loved = books.filter { ($0.rating ?? 0) >= 4 || $0.favorite }
                .sorted { $0.ratingValue > $1.ratingValue }.prefix(30)
                .map { "- \($0.title) by \($0.authorLine)\($0.rating.map { " (rated \($0.formatted()))" } ?? "")" }
            let disliked = books.filter { ($0.rating ?? 5) <= 2 || $0.status == .dnf }.prefix(15)
                .map { "- \($0.title) by \($0.authorLine)\($0.status == .dnf ? " (abandoned)" : "")" }
            let reading = books.filter { $0.status == .reading }.map { "- \($0.title) by \($0.authorLine)" }
            if !loved.isEmpty { out += "\nBooks the reader loved:\n" + loved.joined(separator: "\n") + "\n" }
            if !disliked.isEmpty { out += "\nBooks the reader disliked or abandoned:\n" + disliked.joined(separator: "\n") + "\n" }
            if !reading.isEmpty { out += "\nCurrently reading:\n" + reading.joined(separator: "\n") + "\n" }
            out += "\nAlready in library (do not recommend):\n" + books.prefix(400).map { "- \($0.title) — \($0.authors.first ?? "")" }.joined(separator: "\n") + "\n"
        }
        if !interests.isEmpty { out += "\nReader's stated interests: \(interests.joined(separator: ", "))\n" }
        if !notes.isEmpty {
            out += "\nRelevant notes from the reader (their own words):\n"
                + notes.prefix(12).map { "- [\($0.book.title)] \($0.note.plainText.prefix(300))" }.joined(separator: "\n") + "\n"
        }
        if !dismissed.isEmpty { out += "\nDismissed (do not recommend):\n" + dismissed.prefix(100).map { "- \($0)" }.joined(separator: "\n") + "\n" }
        return out
    }

    /// Verifies candidates against Open Library and maps related titles onto real library books.
    static func verify(_ candidates: [Candidate], books: [Book], dismissed: Set<String>,
                       lookup: @escaping (String, String) async -> [OLDoc]) async -> (recs: [Recommendation], unverified: [String], skipped: Int) {
        let results: [(Int, Candidate, OLDoc?)] = await withTaskGroup(of: (Int, Candidate, OLDoc?).self) { group in
            for (i, c) in candidates.prefix(12).enumerated() {
                group.addTask {
                    let docs = await lookup(c.title, c.author)
                    let match = docs.first { BookMatcher.titlesMatch($0.title, c.title) && BookMatcher.authorsMatch(claimed: c.author, actual: $0.author_name ?? []) }
                    return (i, c, match)
                }
            }
            var all: [(Int, Candidate, OLDoc?)] = []
            for await r in group { all.append(r) }
            return all.sorted { $0.0 < $1.0 }
        }
        var recs: [Recommendation] = []
        var unverified: [String] = []
        var skipped = 0
        var seen = Set<String>()
        for (_, c, doc) in results {
            guard let doc else { unverified.append("\(c.title) — \(c.author)"); continue }
            let inLibrary = books.contains { $0.olWorkKey == doc.key || (BookMatcher.titlesMatch($0.title, doc.title) && BookMatcher.authorsMatch(claimed: $0.authors.first ?? "", actual: doc.author_name ?? [])) }
            if inLibrary || dismissed.contains(doc.key) || !seen.insert(doc.key).inserted { skipped += 1; continue }
            let related = c.related_library_titles.compactMap { t in books.first { BookMatcher.titlesMatch($0.title, t) }?.id }
            recs.append(Recommendation(doc: doc, reason: c.reason, relatedBookIDs: Array(NSOrderedSet(array: related)) as? [UUID] ?? related))
        }
        return (recs, unverified, skipped)
    }

    static func run(query: String, provider: AIProvider, books: [Book], interests: [String], dismissed: [String],
                    shareLibrary: Bool, notes: [NoteRef]) async throws -> DiscoveryResult {
        let request = AIRequest(system: system,
                                user: prompt(query: query, books: books, interests: interests, dismissed: dismissed,
                                             shareLibrary: shareLibrary, notes: notes),
                                schema: schema)
        let response = try await provider.complete(request)
        guard let payload = try? JSONDecoder().decode(Payload.self, from: response.json) else { throw AIError.invalidJSON }
        let verified = await verify(payload.recommendations, books: books, dismissed: Set(dismissed)) { title, author in
            (try? await OpenLibrary.searchTitleAuthor(title: title, author: author)) ?? []
        }
        return DiscoveryResult(recommendations: verified.recs, unverified: verified.unverified,
                               skippedKnown: verified.skipped, provider: provider.displayName)
    }
}
