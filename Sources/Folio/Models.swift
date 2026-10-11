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

struct BookNote: Codable, Hashable, Identifiable {
    var id = UUID()
    var created = Date()
    var text: String
    var page: Int?
    var isQuote: Bool
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
    var subjects: [String] = []
    var synopsis: String?

    var status: ReadingStatus = .wantToRead
    var rating: Double?
    var review: String = ""
    var tags: [String] = []
    var favorite = false
    var dateAdded = Date()
    var dateStarted: Date?
    var dateFinished: Date?
    var currentPage = 0
    var progressLog: [ProgressEntry] = []
    var notes: [BookNote] = []
    var readCount = 0

    var authorLine: String { authors.isEmpty ? "Unknown author" : authors.joined(separator: ", ") }

    var progress: Double {
        guard let pages = pageCount, pages > 0 else { return status == .read ? 1 : 0 }
        return min(1, Double(currentPage) / Double(pages))
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

struct LibraryFile: Codable {
    var books: [Book]
    var goals: [Int: Int]
    var shelves: [String]?
}

/// Stable color derived from a string (Swift's hashValue is randomized per launch).
func stableHue(_ s: String) -> Double {
    var h: UInt64 = 1469598103934665603
    for b in s.utf8 { h = (h ^ UInt64(b)) &* 1099511628211 }
    return Double(h % 360) / 360
}
