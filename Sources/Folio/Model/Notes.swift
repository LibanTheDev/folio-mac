import Foundation

/// A piece of personal knowledge attached to a book.
struct BookNote: Codable, Hashable, Identifiable {
    enum Kind: String, Codable, CaseIterable, Identifiable {
        case highlight, quote, reflection, chapterNote, lesson, mentalModel, takeaway, question
        var id: String { rawValue }

        var title: String {
            switch self {
            case .highlight: "Highlight"
            case .quote: "Quote"
            case .reflection: "Reflection"
            case .chapterNote: "Chapter Note"
            case .lesson: "Key Lesson"
            case .mentalModel: "Mental Model"
            case .takeaway: "Takeaway"
            case .question: "Question"
            }
        }

        var plural: String {
            switch self {
            case .highlight: "Highlights"
            case .quote: "Quotes"
            case .reflection: "Reflections"
            case .chapterNote: "Chapter Notes"
            case .lesson: "Key Lessons"
            case .mentalModel: "Mental Models"
            case .takeaway: "Takeaways"
            case .question: "Questions"
            }
        }

        var symbol: String {
            switch self {
            case .highlight: "highlighter"
            case .quote: "quote.opening"
            case .reflection: "bubble.left"
            case .chapterNote: "list.bullet.rectangle"
            case .lesson: "lightbulb"
            case .mentalModel: "brain"
            case .takeaway: "checkmark.circle"
            case .question: "questionmark.circle"
            }
        }

        /// Verbatim text from the book rather than the reader's own words.
        var isFromBook: Bool { self == .highlight || self == .quote }
    }

    var id = UUID()
    var created = Date()
    var updated = Date()
    var kind: Kind = .reflection
    /// Markdown text.
    var text: String
    var page: Int?
    var chapter: String?
    var tags: [String] = []
    /// Manual connections to notes in this or other books.
    var links: [UUID] = []
    /// Set for notes imported from another app.
    var source: NoteSource?

    /// True when an imported note still matches what was imported (no local edits, tags or links).
    var isUntouchedImport: Bool {
        guard let source else { return false }
        return text == source.importedText && tags.isEmpty && links.isEmpty
    }

    init(id: UUID = UUID(), created: Date = Date(), kind: Kind = .reflection, text: String, page: Int? = nil,
         chapter: String? = nil, tags: [String] = [], links: [UUID] = []) {
        self.id = id; self.created = created; self.updated = created; self.kind = kind; self.text = text
        self.page = page; self.chapter = chapter; self.tags = tags; self.links = links
    }

    /// Convenience for the v1 quote/note distinction.
    init(text: String, page: Int? = nil, isQuote: Bool) {
        self.init(kind: isQuote ? .quote : .reflection, text: text, page: page)
    }

    private enum CodingKeys: String, CodingKey { case id, created, updated, kind, text, page, chapter, tags, links, isQuote, source }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.value(.id, UUID())
        created = c.value(.created, Date())
        updated = c.value(.updated, created)
        text = c.value(.text, "")
        page = c.value(.page, nil)
        chapter = c.value(.chapter, nil)
        tags = c.value(.tags, [])
        links = c.value(.links, [])
        source = c.value(.source, nil)
        if let kind: Kind = c.value(.kind, nil) {
            self.kind = kind
        } else {
            // v1 stored only `isQuote`.
            self.kind = c.value(.isQuote, false) ? .quote : .reflection
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(created, forKey: .created)
        try c.encode(updated, forKey: .updated)
        try c.encode(kind, forKey: .kind)
        try c.encode(text, forKey: .text)
        try c.encodeIfPresent(page, forKey: .page)
        try c.encodeIfPresent(chapter, forKey: .chapter)
        try c.encode(tags, forKey: .tags)
        try c.encode(links, forKey: .links)
        try c.encodeIfPresent(source, forKey: .source)
    }

    var isQuote: Bool { kind.isFromBook }

    /// Text without Markdown syntax, for search and previews.
    var plainText: String {
        (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            .map { String($0.characters) } ?? text
    }

    var locationLabel: String? {
        [chapter.flatMap { $0.isEmpty ? nil : $0 }, page.map { "p. \($0)" }].compactMap { $0 }.joined(separator: " · ").nilIfEmpty
    }
}

/// A note together with the book it belongs to.
struct NoteRef: Hashable, Identifiable {
    let note: BookNote
    let book: Book
    var id: UUID { note.id }
}

extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }

    /// Lenient integer parsing for text inputs: ignores surrounding whitespace, newlines and grouping commas.
    var intValue: Int? {
        Int(trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: ""))
    }
}
