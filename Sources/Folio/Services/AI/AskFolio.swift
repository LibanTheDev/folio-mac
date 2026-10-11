import Foundation

/// Grounded question answering over the reader's own knowledge.
enum AskFolio {
    enum Mode: String, CaseIterable, Identifiable {
        case ask = "Ask", themes = "Recurring Themes", conflicts = "Disagreements", compare = "Compare Authors",
             models = "Mental Models", summary = "Topic Summary"
        var id: String { rawValue }

        var symbol: String {
            switch self {
            case .ask: "bubble.left.and.text.bubble.right"
            case .themes: "repeat"
            case .conflicts: "arrow.left.arrow.right"
            case .compare: "person.2"
            case .models: "brain"
            case .summary: "text.alignleft"
            }
        }

        var placeholder: String {
            switch self {
            case .ask: "What have I learned about how powerful business empires are built?"
            case .themes: "Topic to look for recurring themes in (e.g. capital allocation)"
            case .conflicts: "Which books I've read disagree about centralization?"
            case .compare: "Which authors have discussed incentives and organizational behavior?"
            case .models: "Which mental models keep appearing in my notes on decision-making?"
            case .summary: "Summarize my most important takeaways from business biographies"
            }
        }

        var instruction: String {
            switch self {
            case .ask: "Answer the question."
            case .themes: "Identify recurring themes across the sources, naming which books each theme appears in."
            case .conflicts: "Identify where sources disagree or pull in different directions, and present each side with its sources. If they don't actually conflict, say so."
            case .compare: "Compare how different authors treat the topic: points of agreement, differences in emphasis, and unique contributions."
            case .models: "Extract the mental models (named, reusable ways of thinking) present in the sources, each with a one-line explanation and sources."
            case .summary: "Write a concise synthesis of the reader's most important takeaways on the topic, ordered by importance."
            }
        }
    }

    struct Source: Identifiable, Hashable {
        enum Kind: Hashable { case note(noteID: UUID, bookID: UUID), metadata(bookID: UUID) }
        let id: String          // "S1", "M1"
        let kind: Kind
        let title: String       // book title
        let label: String       // e.g. "Key Lesson · p. 42"
        let text: String
    }

    enum SectionKind: String, Decodable, CaseIterable {
        case from_your_notes, from_book_metadata, general_knowledge
        var title: String {
            switch self {
            case .from_your_notes: "From your notes"
            case .from_book_metadata: "From book information"
            case .general_knowledge: "General knowledge (AI, not from your library)"
            }
        }
    }

    struct Paragraph: Hashable {
        var text: String
        var citations: [String]
        /// Citations the model gave that don't exist in the sources.
        var invalidCitations: [String]
        /// Quoted phrases that couldn't be found verbatim in any source.
        var unverifiedQuotes: [String]
        /// A claim about the reader's own reading with no valid source.
        var unsupported: Bool
    }

    struct Section: Hashable { let kind: SectionKind; var paragraphs: [Paragraph] }

    struct Answer {
        var question: String
        var mode: Mode
        var sections: [Section]
        var insufficientEvidence: Bool
        var sources: [Source]
        var provider: String
    }

    // MARK: Retrieval

    /// Finds the most relevant notes (by keyword and meaning) plus metadata for the books they come from.
    @MainActor
    static func retrieve(_ question: String, books: [Book], index: EmbeddingIndex, maxNotes: Int = 16) -> [Source] {
        var noteRefs: [NoteRef] = []
        var seen = Set<UUID>()
        let byID = Dictionary(uniqueKeysWithValues: books.map { ($0.id, $0) })
        func add(_ ref: NoteRef) { if seen.insert(ref.note.id).inserted { noteRefs.append(ref) } }

        // Looser keyword coverage than global search: retrieval should rank, not exclude.
        for hit in index.hybridSearch(question, books: books, limit: 40, minCoverage: 0.25) {
            if case .note(let nid, let bid) = hit.source, let b = byID[bid], let n = b.notes.first(where: { $0.id == nid }) {
                add(NoteRef(note: n, book: b))
            }
        }
        // Books or authors named in the question bring their notes along.
        let q = question.lowercased()
        for b in books where q.contains(b.title.lowercased()) || b.authors.contains(where: { a in
            a.split(separator: " ").last.map { q.contains($0.lowercased()) && $0.count > 3 } ?? false
        }) {
            for n in b.notes.prefix(6) { add(NoteRef(note: n, book: b)) }
        }
        noteRefs = Array(noteRefs.prefix(maxNotes))

        var sources: [Source] = noteRefs.enumerated().map { i, r in
            Source(id: "S\(i + 1)", kind: .note(noteID: r.note.id, bookID: r.book.id), title: r.book.title,
                   label: [r.note.kind.title, r.note.locationLabel].compactMap { $0 }.joined(separator: " · "),
                   text: String(r.note.plainText.prefix(700)))
        }
        var bookOrder: [UUID] = []
        for r in noteRefs where !bookOrder.contains(r.book.id) { bookOrder.append(r.book.id) }
        for (i, id) in bookOrder.prefix(10).enumerated() {
            guard let b = byID[id] else { continue }
            var facts = ["\(b.title) by \(b.authorLine)"]
            if let y = b.publishYear { facts.append("published \(y)") }
            facts.append("reader status: \(b.status.title.lowercased())")
            if let r = b.rating { facts.append("reader rating \(r.formatted())/5") }
            if let s = b.synopsis, !s.isEmpty { facts.append("description: \(s.prefix(450))") }
            sources.append(Source(id: "M\(i + 1)", kind: .metadata(bookID: b.id), title: b.title, label: "Book information",
                                  text: facts.joined(separator: "; ")))
        }
        return sources
    }

    // MARK: Prompt

    static let system = """
    You are Ask Folio, an assistant that helps a reader understand what they have learned from their own reading.
    You are given numbered sources: S-sources are the reader's own saved notes and highlights; M-sources are basic \
    information about books in their library.

    Ground rules:
    - Every statement about what the reader has read, noted or learned must cite at least one S-source, like "S2".
    - Book facts (author, year, what a book is about) cite M-sources.
    - You may add general background knowledge only in the general_knowledge section, without citations, and \
    never present it as coming from the reader's notes. Do not describe the contents of specific books beyond \
    what the sources say.
    - Never invent quotations, page numbers or citations. Only put text in quotation marks if it appears verbatim \
    in a source.
    - If the sources don't contain enough to answer, set insufficient_evidence to true and say what is missing; \
    keep sections short rather than speculating.
    - Write clearly and concisely. Each paragraph should be 1–4 sentences.
    """

    static let schema: [String: Any] = [
        "type": "object",
        "properties": [
            "insufficient_evidence": ["type": "boolean"],
            "sections": [
                "type": "array",
                "items": [
                    "type": "object",
                    "properties": [
                        "kind": ["type": "string", "enum": ["from_your_notes", "from_book_metadata", "general_knowledge"]],
                        "paragraphs": [
                            "type": "array",
                            "items": [
                                "type": "object",
                                "properties": [
                                    "text": ["type": "string"],
                                    "citations": ["type": "array", "items": ["type": "string"]],
                                ],
                                "required": ["text", "citations"],
                                "additionalProperties": false,
                            ],
                        ],
                    ],
                    "required": ["kind", "paragraphs"],
                    "additionalProperties": false,
                ],
            ],
        ],
        "required": ["insufficient_evidence", "sections"],
        "additionalProperties": false,
    ]

    static func prompt(question: String, mode: Mode, sources: [Source]) -> String {
        var out = "Task: \(mode.instruction)\n\nQuestion: \(question)\n\nSources:\n"
        for s in sources {
            out += "[\(s.id)] (\(s.title)\(s.label.isEmpty ? "" : " — \(s.label)")) \(s.text)\n"
        }
        if sources.isEmpty { out += "(none: the reader has no saved notes relevant to this question)\n" }
        return out
    }

    // MARK: Validation

    struct RawAnswer: Decodable {
        struct RawSection: Decodable {
            let kind: SectionKind
            let paragraphs: [RawParagraph]
        }
        struct RawParagraph: Decodable { let text: String; let citations: [String] }
        let insufficient_evidence: Bool
        let sections: [RawSection]
    }

    static func normalizeForQuote(_ s: String) -> String {
        s.lowercased()
            .replacingOccurrences(of: "\u{2019}", with: "'")
            .components(separatedBy: CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "'")).inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    /// Quoted phrases (straight or curly quotes) of at least three words.
    static func quotes(in text: String) -> [String] {
        let pattern = #"[“"]([^”"]{8,})[”"]"#
        guard let re = try? NSRegularExpression(pattern: pattern) else { return [] }
        let ns = text as NSString
        return re.matches(in: text, range: NSRange(location: 0, length: ns.length)).compactMap { m in
            let q = ns.substring(with: m.range(at: 1))
            return q.split(separator: " ").count >= 3 ? q : nil
        }
    }

    /// Checks every citation and quotation against the sources that were actually provided.
    static func validate(_ raw: RawAnswer, sources: [Source]) -> (sections: [Section], insufficient: Bool) {
        let ids = Set(sources.map(\.id))
        let corpus = sources.map { normalizeForQuote($0.text) }
        let sections: [Section] = raw.sections.map { sec in
            Section(kind: sec.kind, paragraphs: sec.paragraphs.map { p in
                let cleaned = p.citations.map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "[] ")) }
                let valid = cleaned.filter { ids.contains($0) }
                let invalid = cleaned.filter { !ids.contains($0) }
                let unverified = quotes(in: p.text).filter { q in
                    let nq = normalizeForQuote(q)
                    return !corpus.contains { $0.contains(nq) }
                }
                let needsNoteSource = sec.kind == .from_your_notes
                let hasNoteSource = valid.contains { $0.hasPrefix("S") }
                let hasAnySource = !valid.isEmpty
                let unsupported = needsNoteSource ? !hasNoteSource : (sec.kind == .from_book_metadata && !hasAnySource)
                return Paragraph(text: p.text, citations: valid, invalidCitations: invalid,
                                 unverifiedQuotes: unverified, unsupported: unsupported)
            })
        }
        .filter { !$0.paragraphs.isEmpty }
        .sorted { SectionKind.allCases.firstIndex(of: $0.kind)! < SectionKind.allCases.firstIndex(of: $1.kind)! }
        let noteSupported = sections.contains { $0.kind == .from_your_notes && $0.paragraphs.contains { !$0.unsupported } }
        return (sections, raw.insufficient_evidence || !noteSupported)
    }

    @MainActor
    static func run(question: String, mode: Mode, provider: AIProvider, books: [Book], index: EmbeddingIndex) async throws -> Answer {
        let sources = retrieve(question, books: books, index: index)
        let response = try await provider.complete(AIRequest(system: system, user: prompt(question: question, mode: mode, sources: sources),
                                                             schema: schema))
        guard let raw = try? JSONDecoder().decode(RawAnswer.self, from: response.json) else { throw AIError.invalidJSON }
        let v = validate(raw, sources: sources)
        return Answer(question: question, mode: mode, sections: v.sections, insufficientEvidence: v.insufficient,
                      sources: sources, provider: provider.displayName)
    }
}
