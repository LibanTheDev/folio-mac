import Foundation

enum Related {
    /// Books in the library related to `book`, ranked by shared author, shelves, genres and tags.
    static func books(for book: Book, in library: [Book], shelves: [Shelf], limit: Int = 8) -> [Book] {
        let myShelves = Set(shelves.filter { $0.contains(book) }.map(\.id))
        let myGenres = Set(book.genres.map { $0.lowercased() })
        let myTags = Set(book.tags)
        let myAuthors = Set(book.authors)
        let scored: [(Book, Int)] = library.compactMap { other in
            guard other.id != book.id else { return nil }
            var score = 0
            if !myAuthors.isDisjoint(with: other.authors) { score += 4 }
            score += 2 * shelves.filter { myShelves.contains($0.id) && $0.contains(other) }.count
            score += Set(other.genres.map { $0.lowercased() }).intersection(myGenres).count
            score += Set(other.tags).intersection(myTags).count
            return score > 0 ? (other, score) : nil
        }
        return scored.sorted { $0.1 > $1.1 || ($0.1 == $1.1 && $0.0.title < $1.0.title) }.prefix(limit).map(\.0)
    }
}
