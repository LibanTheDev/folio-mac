import Foundation

struct OLDoc: Decodable, Identifiable, Hashable {
    let key: String
    let title: String
    let author_name: [String]?
    let first_publish_year: Int?
    let cover_i: Int?
    let number_of_pages_median: Int?
    let isbn: [String]?
    let subject: [String]?
    let publisher: [String]?
    let ratings_average: Double?
    let ratings_count: Int?

    var id: String { key }
    var authorLine: String { (author_name ?? ["Unknown author"]).prefix(2).joined(separator: ", ") }

    var preferredISBN: String? {
        isbn?.first(where: { $0.count == 13 }) ?? isbn?.first
    }

    var coverURL: URL? {
        cover_i.flatMap { URL(string: "https://covers.openlibrary.org/b/id/\($0)-M.jpg") }
    }
}

private struct SearchResponse: Decodable { let docs: [OLDoc] }
private struct TrendingResponse: Decodable { let works: [OLDoc] }

private struct WorkResponse: Decodable {
    let description: Description?
    enum Description: Decodable {
        case text(String)
        init(from decoder: Decoder) throws {
            let c = try decoder.singleValueContainer()
            if let s = try? c.decode(String.self) { self = .text(s); return }
            struct Obj: Decodable { let value: String }
            self = .text(try c.decode(Obj.self).value)
        }
        var string: String { if case .text(let s) = self { return s }; return "" }
    }
}

enum OpenLibrary {
    private static let fields = "key,title,author_name,first_publish_year,cover_i,number_of_pages_median,isbn,subject,publisher,ratings_average,ratings_count"

    private static func get<T: Decodable>(_ url: URL, as: T.Type) async throws -> T {
        var req = URLRequest(url: url)
        req.setValue("Folio/1.0 (macOS reading tracker)", forHTTPHeaderField: "User-Agent")
        let (data, _) = try await URLSession.shared.data(for: req)
        return try JSONDecoder().decode(T.self, from: data)
    }

    static func search(_ query: String, limit: Int = 40) async throws -> [OLDoc] {
        var c = URLComponents(string: "https://openlibrary.org/search.json")!
        c.queryItems = [.init(name: "q", value: query), .init(name: "limit", value: "\(limit)"), .init(name: "fields", value: fields)]
        return try await get(c.url!, as: SearchResponse.self).docs
    }

    static func lookup(isbn: String?, title: String, author: String?) async -> OLDoc? {
        var c = URLComponents(string: "https://openlibrary.org/search.json")!
        var items: [URLQueryItem] = [.init(name: "limit", value: "1"), .init(name: "fields", value: fields)]
        if let isbn, !isbn.isEmpty {
            items.append(.init(name: "isbn", value: isbn))
        } else {
            items.append(.init(name: "title", value: title))
            if let author { items.append(.init(name: "author", value: author)) }
        }
        c.queryItems = items
        return try? await get(c.url!, as: SearchResponse.self).docs.first
    }

    static func trending() async throws -> [OLDoc] {
        try await get(URL(string: "https://openlibrary.org/trending/weekly.json?limit=40")!, as: TrendingResponse.self).works
    }

    static func subject(_ name: String) async throws -> [OLDoc] {
        try await search("subject:\"\(name)\"", limit: 40)
    }

    static func description(workKey: String) async -> String? {
        guard let url = URL(string: "https://openlibrary.org\(workKey).json"),
              let work = try? await get(url, as: WorkResponse.self),
              let text = work.description?.string, !text.isEmpty else { return nil }
        // Strip OL's trailing source links / markdown separators.
        let cleaned = text.components(separatedBy: "\n----------").first ?? text
        return cleaned
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: #"(?m)^\s*\[\d+\]:\s*\S+.*$"#, with: "", options: .regularExpression)  // [1]: http://…
            .replacingOccurrences(of: #"\[([^\]]+)\]\[\d+\]"#, with: "$1", options: .regularExpression)        // [text][1]
            .replacingOccurrences(of: #"\[([^\]]+)\]\([^)]*\)"#, with: "$1", options: .regularExpression)       // [text](url)
            .replacingOccurrences(of: #"(?m)^>\s?"#, with: "", options: .regularExpression)                     // > quote
            .replacingOccurrences(of: #"(?m)^\s*\((source|Source)[^)]*\)\s*$"#, with: "", options: .regularExpression) // (source)
            .replacingOccurrences(of: #"\n{3,}"#, with: "\n\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
