import Foundation

/// Facets for narrowing the library. Every non-empty facet must match (AND); values within a facet are OR.
struct LibraryFilter: Equatable {
    var statuses: Set<ReadingStatus> = []
    var authors: Set<String> = []
    var genres: Set<String> = []
    var tags: Set<String> = []
    var shelfIDs: Set<UUID> = []
    var minRating: Double?
    var unratedOnly = false
    var favoritesOnly = false
    var publishedFrom: Int?
    var publishedTo: Int?
    var minPages: Int?
    var maxPages: Int?
    var addedWithinDays: Int?
    var completedYear: Int?

    var isEmpty: Bool { self == LibraryFilter() }

    func matches(_ b: Book, shelves: [Shelf], now: Date = Date()) -> Bool {
        if !statuses.isEmpty, !statuses.contains(b.status) { return false }
        if !authors.isEmpty, !b.authors.contains(where: authors.contains) { return false }
        if !genres.isEmpty, !b.genres.contains(where: genres.contains) { return false }
        if !tags.isEmpty, !b.tags.contains(where: tags.contains) { return false }
        if !shelfIDs.isEmpty {
            let hit = shelves.contains { shelfIDs.contains($0.id) && $0.contains(b, now: now) }
            if !hit { return false }
        }
        if let minRating, (b.rating ?? 0) < minRating { return false }
        if unratedOnly, b.rating != nil { return false }
        if favoritesOnly, !b.favorite { return false }
        if let publishedFrom, (b.publishYear ?? Int.min) < publishedFrom { return false }
        if let publishedTo, (b.publishYear ?? Int.max) > publishedTo { return false }
        if let minPages, (b.pageCount ?? 0) < minPages { return false }
        if let maxPages, (b.pageCount ?? Int.max) > maxPages { return false }
        if let addedWithinDays, now.timeIntervalSince(b.dateAdded) > Double(addedWithinDays) * 86_400 { return false }
        if let completedYear {
            guard b.status == .read, let d = b.dateFinished, Calendar.current.component(.year, from: d) == completedYear else { return false }
        }
        return true
    }

    struct Token: Identifiable, Hashable {
        let id: String
        let label: String
    }

    /// Removable chips describing the active facets.
    func tokens(shelfName: (UUID) -> String?) -> [Token] {
        var t: [Token] = []
        for s in statuses.sorted(by: { $0.rawValue < $1.rawValue }) { t.append(.init(id: "status:\(s.rawValue)", label: s.title)) }
        for a in authors.sorted() { t.append(.init(id: "author:\(a)", label: a)) }
        for g in genres.sorted() { t.append(.init(id: "genre:\(g)", label: g)) }
        for tag in tags.sorted() { t.append(.init(id: "tag:\(tag)", label: "#\(tag)")) }
        for id in shelfIDs { t.append(.init(id: "shelf:\(id.uuidString)", label: shelfName(id) ?? "Shelf")) }
        if let minRating { t.append(.init(id: "rating", label: "\(minRating.formatted())★ & up")) }
        if unratedOnly { t.append(.init(id: "unrated", label: "Unrated")) }
        if favoritesOnly { t.append(.init(id: "favorites", label: "Favourites")) }
        if publishedFrom != nil || publishedTo != nil {
            t.append(.init(id: "published", label: "Published \(publishedFrom.map(String.init) ?? "…")–\(publishedTo.map(String.init) ?? "…")"))
        }
        if minPages != nil || maxPages != nil {
            t.append(.init(id: "pages", label: "\(minPages.map(String.init) ?? "0")–\(maxPages.map(String.init) ?? "∞") pages"))
        }
        if let addedWithinDays { t.append(.init(id: "added", label: "Added in last \(addedWithinDays) days")) }
        if let completedYear { t.append(.init(id: "completed", label: "Read in \(completedYear)")) }
        return t
    }

    mutating func remove(_ tokenID: String) {
        let parts = tokenID.split(separator: ":", maxSplits: 1).map(String.init)
        let value = parts.count > 1 ? parts[1] : ""
        switch parts[0] {
        case "status": if let s = ReadingStatus(rawValue: value) { statuses.remove(s) }
        case "author": authors.remove(value)
        case "genre": genres.remove(value)
        case "tag": tags.remove(value)
        case "shelf": if let id = UUID(uuidString: value) { shelfIDs.remove(id) }
        case "rating": minRating = nil
        case "unrated": unratedOnly = false
        case "favorites": favoritesOnly = false
        case "published": publishedFrom = nil; publishedTo = nil
        case "pages": minPages = nil; maxPages = nil
        case "added": addedWithinDays = nil
        case "completed": completedYear = nil
        default: break
        }
    }
}

/// Library sort orders.
enum SortKey: String, CaseIterable, Identifiable {
    case added = "Date Added", title = "Title", author = "Author", rating = "My Rating",
         finished = "Date Completed", pages = "Length", published = "Publication Year", manual = "Shelf Order"
    var id: String { rawValue }

    var comparator: KeyPathComparator<Book> {
        switch self {
        case .added, .manual: KeyPathComparator(\Book.dateAdded, order: .reverse)
        case .title: KeyPathComparator(\Book.sortTitle)
        case .author: KeyPathComparator(\Book.sortAuthor)
        case .rating: KeyPathComparator(\Book.ratingValue, order: .reverse)
        case .finished: KeyPathComparator(\Book.finishedValue, order: .reverse)
        case .pages: KeyPathComparator(\Book.pagesValue, order: .reverse)
        case .published: KeyPathComparator(\Book.publishedValue, order: .reverse)
        }
    }
}

extension Book {
    var publishedValue: Int { publishYear ?? Int.min }
}
