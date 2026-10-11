import Foundation
import SwiftUI

enum ReadingStatus: String, Codable, CaseIterable, Identifiable {
    case wantToRead, reading, read, dnf

    var id: String { rawValue }

    var title: String {
        switch self {
        case .wantToRead: "Want to Read"
        case .reading: "Currently Reading"
        case .read: "Read"
        case .dnf: "Did Not Finish"
        }
    }

    var shortTitle: String {
        switch self {
        case .wantToRead: "Want"
        case .reading: "Reading"
        case .read: "Read"
        case .dnf: "DNF"
        }
    }

    var symbol: String {
        switch self {
        case .wantToRead: "clock"
        case .reading: "book"
        case .read: "checkmark.circle"
        case .dnf: "hand.raised"
        }
    }

    var tint: Color {
        switch self {
        case .wantToRead: DS.statusWant
        case .reading: DS.statusReading
        case .read: DS.statusRead
        case .dnf: DS.statusDNF
        }
    }

    var boardTitle: String {
        switch self {
        case .wantToRead: "To Be Read"
        case .reading: "In Progress"
        case .read: "Completed"
        case .dnf: "Did Not Finish"
        }
    }
}

struct ProgressEntry: Codable, Hashable, Identifiable {
    var id = UUID()
    var date: Date
    var page: Int
}

/// One completed (or abandoned) pass through a book. Rereads append here instead of overwriting.
struct ReadThrough: Codable, Hashable, Identifiable {
    enum Outcome: String, Codable { case finished, abandoned }
    var id = UUID()
    var started: Date?
    var finished: Date?
    var outcome: Outcome = .finished
    var rating: Double?

    init(id: UUID = UUID(), started: Date?, finished: Date?, outcome: Outcome = .finished, rating: Double? = nil) {
        self.id = id; self.started = started; self.finished = finished; self.outcome = outcome; self.rating = rating
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.value(.id, UUID())
        started = c.value(.started, nil)
        finished = c.value(.finished, nil)
        outcome = c.value(.outcome, .finished)
        rating = c.value(.rating, nil)
    }
}

struct Book: Codable, Hashable, Identifiable {
    var id = UUID()
    var title: String
    var authors: [String]
    var isbn: String?
    var olWorkKey: String?
    var coverID: Int?
    var pageCount: Int?
    var publishYear: Int?
    var publisher: String?
    var edition: String?
    var format: String?
    var language: String?
    var subjects: [String] = []
    var synopsis: String?

    var status: ReadingStatus = .wantToRead
    var rating: Double?
    var review: String = ""
    var tags: [String] = []
    var favorite = false
    var dateAdded = Date()
    var updatedAt = Date()
    /// Dates of the current (most recent) read-through.
    var dateStarted: Date?
    var dateFinished: Date?
    var currentPage = 0
    var progressLog: [ProgressEntry] = []
    var notes: [BookNote] = []
    var readCount = 0
    /// Earlier read-throughs, oldest first.
    var history: [ReadThrough] = []
    /// Position in the Up Next queue (lower comes first). Nil means unordered.
    var queueRank: Double?
    /// Apple Books asset ID (`ZASSETID`) when this book is linked to Apple Books.
    var appleBooksID: String?
    /// Progress reported by an external app. Kept separate from Folio's own page log so the UI can say
    /// exactly where a number came from.
    var externalProgress: ExternalProgress?

    init(id: UUID = UUID(), title: String, authors: [String], isbn: String? = nil, olWorkKey: String? = nil,
         coverID: Int? = nil, pageCount: Int? = nil, publishYear: Int? = nil, publisher: String? = nil,
         subjects: [String] = []) {
        self.id = id; self.title = title; self.authors = authors; self.isbn = isbn; self.olWorkKey = olWorkKey
        self.coverID = coverID; self.pageCount = pageCount; self.publishYear = publishYear; self.publisher = publisher
        self.subjects = subjects
    }

    /// Tolerant decoding: every field except the title has a default, so older or partially
    /// damaged files still load instead of failing as a whole.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.value(.id, UUID())
        title = try c.decode(String.self, forKey: .title)
        authors = c.value(.authors, [])
        isbn = c.value(.isbn, nil)
        olWorkKey = c.value(.olWorkKey, nil)
        coverID = c.value(.coverID, nil)
        pageCount = c.value(.pageCount, nil)
        publishYear = c.value(.publishYear, nil)
        publisher = c.value(.publisher, nil)
        edition = c.value(.edition, nil)
        format = c.value(.format, nil)
        language = c.value(.language, nil)
        subjects = c.value(.subjects, [])
        synopsis = c.value(.synopsis, nil)
        status = c.value(.status, .wantToRead)
        rating = c.value(.rating, nil)
        review = c.value(.review, "")
        tags = c.value(.tags, [])
        favorite = c.value(.favorite, false)
        dateAdded = c.value(.dateAdded, Date())
        updatedAt = c.value(.updatedAt, dateAdded)
        dateStarted = c.value(.dateStarted, nil)
        dateFinished = c.value(.dateFinished, nil)
        currentPage = c.value(.currentPage, 0)
        progressLog = c.value(.progressLog, [])
        notes = c.value(.notes, [])
        readCount = c.value(.readCount, 0)
        history = c.value(.history, [])
        queueRank = c.value(.queueRank, nil)
        appleBooksID = c.value(.appleBooksID, nil)
        externalProgress = c.value(.externalProgress, nil)
    }

    /// All read-throughs including the current one, oldest first.
    var allReadThroughs: [ReadThrough] {
        var all = history
        if dateStarted != nil || dateFinished != nil {
            all.append(ReadThrough(started: dateStarted, finished: status == .read ? dateFinished : nil,
                                   outcome: status == .dnf ? .abandoned : .finished, rating: rating))
        }
        return all
    }

    var genres: [String] { Self.cleanLabels(subjects) }

    var authorLine: String { authors.isEmpty ? "Unknown author" : authors.joined(separator: ", ") }

    var progress: Double {
        if let pages = pageCount, pages > 0, currentPage > 0 {
            return min(1, Double(currentPage) / Double(pages))
        }
        if let e = externalProgress { return e.finished ? 1 : min(1, max(0, e.fraction)) }
        return status == .read ? 1 : 0
    }

    /// Where the displayed progress comes from.
    enum ProgressProvenance: Equatable { case loggedInFolio, confirmedByAppleBooks, unknown }

    var progressProvenance: ProgressProvenance {
        if let pages = pageCount, pages > 0, currentPage > 0 { return .loggedInFolio }
        if externalProgress != nil { return .confirmedByAppleBooks }
        return .unknown
    }

    /// Short genre-ish labels for cards: user shelves first, then tidy Open Library subjects.
    var chips: [String] { Array(Self.cleanLabels(tags + subjects).prefix(4)) }

    private static let aliases: [String: String] = [
        "scifi": "Sci-Fi", "sciencefiction": "Sci-Fi", "fictionsciencefiction": "Sci-Fi",
        "fantasyfiction": "Fantasy", "ya": "Young Adult", "youngadultfiction": "Young Adult",
        "nonfiction": "Nonfiction", "biographyautobiography": "Biography", "selfhelp": "Self-Help",
    ]
    private static let noise: Set<String> = ["fiction", "general", "literature", "novel", "novels", "nytbestseller", "largetypebooks", "openlibrarystaffpicks", "accessiblebookcollection", "protecteddaisy", "inlibrary", "lendinglibrary", "englishlanguage"]

    static func cleanLabels(_ raw: [String]) -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        for r in raw {
            // Skip long, compound, or non-English-looking subjects.
            guard r.count <= 22, !r.contains(","), !r.contains(":"), !r.contains("("),
                  r.unicodeScalars.allSatisfy({ $0.isASCII }) else { continue }
            let key = r.lowercased().filter(\.isLetter)
            guard !key.isEmpty, !noise.contains(key) else { continue }
            let label = aliases[key] ?? r.replacingOccurrences(of: "-", with: " ").capitalized
            let labelKey = label.lowercased().filter(\.isLetter)
            if seen.insert(labelKey).inserted { out.append(label) }
        }
        return out
    }

    func coverURL(size: String = "M") -> URL? {
        if let coverID { return URL(string: "https://covers.openlibrary.org/b/id/\(coverID)-\(size).jpg") }
        if let isbn, !isbn.isEmpty { return URL(string: "https://covers.openlibrary.org/b/isbn/\(isbn)-\(size).jpg?default=false") }
        return nil
    }

    // Non-optional keys for sorting in tables.
    var sortTitle: String { title.lowercased().replacingOccurrences(of: "^(the|a|an) ", with: "", options: .regularExpression) }
    var sortAuthor: String { (authors.first?.split(separator: " ").last.map(String.init) ?? "").lowercased() }
    var ratingValue: Double { rating ?? 0 }
    var pagesValue: Int { pageCount ?? 0 }
    var finishedValue: Date { dateFinished ?? .distantPast }
    var statusValue: String { status.rawValue }
}

extension Book {
    init(from doc: OLDoc) {
        self.init(
            title: doc.title,
            authors: doc.author_name ?? [],
            isbn: doc.preferredISBN,
            olWorkKey: doc.key,
            coverID: doc.cover_i,
            pageCount: doc.number_of_pages_median,
            publishYear: doc.first_publish_year,
            publisher: doc.publisher?.first,
            subjects: Array((doc.subject ?? []).prefix(8))
        )
    }
}

/// Stable color derived from a string (Swift's hashValue is randomized per launch).
func stableHue(_ s: String) -> Double {
    var h: UInt64 = 1469598103934665603
    for b in s.utf8 { h = (h ^ UInt64(b)) &* 1099511628211 }
    return Double(h % 360) / 360
}
