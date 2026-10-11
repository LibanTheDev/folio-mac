import Foundation

/// A user collection: either a manual, ordered list of books or a smart shelf defined by rules.
struct Shelf: Codable, Hashable, Identifiable {
    enum Kind: String, Codable { case manual, smart }

    var id = UUID()
    var name: String
    var icon: String = "books.vertical"
    var kind: Kind = .manual
    /// Manual shelves: ordered member IDs.
    var bookIDs: [UUID] = []
    /// Smart shelves: rules combined with AND (`matchAll`) or OR.
    var rules: [ShelfRule] = []
    var matchAll = true

    init(id: UUID = UUID(), name: String, icon: String = "books.vertical", kind: Kind = .manual,
         bookIDs: [UUID] = [], rules: [ShelfRule] = [], matchAll: Bool = true) {
        self.id = id; self.name = name; self.icon = icon; self.kind = kind
        self.bookIDs = bookIDs; self.rules = rules; self.matchAll = matchAll
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.value(.id, UUID())
        name = c.value(.name, "Untitled Shelf")
        icon = c.value(.icon, "books.vertical")
        kind = c.value(.kind, .manual)
        bookIDs = c.value(.bookIDs, [])
        rules = c.value(.rules, [])
        matchAll = c.value(.matchAll, true)
    }

    func contains(_ book: Book, now: Date = Date()) -> Bool {
        switch kind {
        case .manual:
            return bookIDs.contains(book.id)
        case .smart:
            guard !rules.isEmpty else { return false }
            return matchAll ? rules.allSatisfy { $0.matches(book, now: now) } : rules.contains { $0.matches(book, now: now) }
        }
    }
}

struct ShelfRule: Codable, Hashable, Identifiable {
    enum Field: String, Codable, CaseIterable, Identifiable {
        case status, rating, author, genre, tag, title, finishedYear, finishedWithinDays, addedWithinDays,
             pages, publicationYear, favorite, readCount
        var id: String { rawValue }

        var title: String {
            switch self {
            case .status: "Status"
            case .rating: "My rating"
            case .author: "Author"
            case .genre: "Genre / subject"
            case .tag: "Tag"
            case .title: "Title"
            case .finishedYear: "Year finished"
            case .finishedWithinDays: "Finished within (days)"
            case .addedWithinDays: "Added within (days)"
            case .pages: "Page count"
            case .publicationYear: "Publication year"
            case .favorite: "Favourite"
            case .readCount: "Times read"
            }
        }

        var isNumeric: Bool {
            switch self {
            case .rating, .finishedYear, .finishedWithinDays, .addedWithinDays, .pages, .publicationYear, .readCount: true
            default: false
            }
        }

        var allowedOps: [Op] {
            switch self {
            case .status, .favorite: [.is, .isNot]
            case .finishedWithinDays, .addedWithinDays: [.atMost]
            case .author, .genre, .tag, .title: [.contains, .notContains, .is]
            default: [.is, .atLeast, .atMost]
            }
        }
    }

    enum Op: String, Codable, CaseIterable, Identifiable {
        case `is`, isNot, contains, notContains, atLeast, atMost
        var id: String { rawValue }
        var title: String {
            switch self {
            case .is: "is"
            case .isNot: "is not"
            case .contains: "contains"
            case .notContains: "does not contain"
            case .atLeast: "at least"
            case .atMost: "at most"
            }
        }
    }

    var id = UUID()
    var field: Field
    var op: Op
    var value: String

    init(id: UUID = UUID(), _ field: Field, _ op: Op, _ value: String) {
        self.id = id; self.field = field; self.op = op; self.value = value
    }

    func matches(_ b: Book, now: Date = Date()) -> Bool {
        let cal = Calendar.current
        switch field {
        case .status:
            let hit = b.status.rawValue == value
            return op == .isNot ? !hit : hit
        case .favorite:
            let want = value == "true"
            return op == .isNot ? b.favorite != want : b.favorite == want
        case .author: return text(b.authors.joined(separator: " | "))
        case .title: return text(b.title)
        case .genre: return list(b.genres + b.subjects)
        case .tag: return list(b.tags)
        case .rating: return number(b.rating)
        case .pages: return number(b.pageCount.map(Double.init))
        case .publicationYear: return number(b.publishYear.map(Double.init))
        case .readCount: return number(Double(b.readCount))
        case .finishedYear:
            return number(b.status == .read ? b.dateFinished.map { Double(cal.component(.year, from: $0)) } : nil)
        case .finishedWithinDays:
            guard b.status == .read, let d = b.dateFinished, let n = Double(value) else { return false }
            return now.timeIntervalSince(d) <= n * 86_400 && d <= now
        case .addedWithinDays:
            guard let n = Double(value) else { return false }
            return now.timeIntervalSince(b.dateAdded) <= n * 86_400
        }
    }

    private func text(_ s: String) -> Bool {
        let needle = value.lowercased().trimmingCharacters(in: .whitespaces)
        guard !needle.isEmpty else { return true }
        switch op {
        case .is: return s.lowercased() == needle || s.lowercased().split(separator: "|").map { $0.trimmingCharacters(in: .whitespaces) }.contains(needle)
        case .notContains: return !s.lowercased().contains(needle)
        default: return s.lowercased().contains(needle)
        }
    }

    private func list(_ items: [String]) -> Bool {
        let needle = value.lowercased().trimmingCharacters(in: .whitespaces)
        let lowered = items.map { $0.lowercased() }
        switch op {
        case .is: return lowered.contains(needle)
        case .notContains: return !lowered.contains { $0.contains(needle) }
        default: return lowered.contains { $0.contains(needle) }
        }
    }

    private func number(_ v: Double?) -> Bool {
        guard let v, let target = Double(value) else { return false }
        switch op {
        case .atLeast: return v >= target
        case .atMost: return v <= target
        case .isNot: return v != target
        default: return v == target
        }
    }
}

extension Shelf {
    /// Ready-made smart shelves offered when creating a new one.
    static func templates(year: Int) -> [Shelf] {
        [
            Shelf(name: "Best Books of \(year)", icon: "trophy", kind: .smart,
                  rules: [ShelfRule(.finishedYear, .is, "\(year)"), ShelfRule(.rating, .atLeast, "4")]),
            Shelf(name: "Recently Finished", icon: "checkmark.seal", kind: .smart,
                  rules: [ShelfRule(.finishedWithinDays, .atMost, "90")]),
            Shelf(name: "Unfinished Books", icon: "hand.raised", kind: .smart,
                  rules: [ShelfRule(.status, .is, ReadingStatus.dnf.rawValue)]),
            Shelf(name: "Long Reads", icon: "ruler", kind: .smart,
                  rules: [ShelfRule(.pages, .atLeast, "500")]),
            Shelf(name: "Want to Reread", icon: "arrow.counterclockwise", kind: .smart,
                  rules: [ShelfRule(.status, .is, ReadingStatus.read.rawValue), ShelfRule(.rating, .atLeast, "4.5")]),
            Shelf(name: "Investing", icon: "chart.line.uptrend.xyaxis", kind: .smart,
                  rules: [ShelfRule(.genre, .contains, "invest"), ShelfRule(.tag, .contains, "invest")], matchAll: false),
            Shelf(name: "Business Biographies", icon: "person.text.rectangle", kind: .smart,
                  rules: [ShelfRule(.genre, .contains, "biograph"), ShelfRule(.genre, .contains, "business")]),
        ]
    }
}
