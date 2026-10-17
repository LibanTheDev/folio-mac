import Foundation

/// Catalogs Folio may download EPUBs from. Only providers whose catalogs are public-domain or openly
/// licensed are allowed; Folio never lists or downloads from unlicensed sources.
enum EbookProviderID: String, Codable, CaseIterable, Identifiable {
    case standardEbooks, gutenberg
    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .standardEbooks: "Standard Ebooks"
        case .gutenberg: "Project Gutenberg"
        }
    }

    var tagline: String {
        switch self {
        case .standardEbooks: "Carefully proofread, beautifully typeset public-domain editions"
        case .gutenberg: "The original free library of public-domain books"
        }
    }
}

/// One downloadable edition of a book.
struct EbookEdition: Identifiable, Hashable {
    var provider: EbookProviderID
    var title: String
    var authors: [String]
    var language: String?
    /// Original publication year, only when the provider states it.
    var year: Int?
    var fileSize: Int64?
    var formatLabel: String
    var downloadURL: URL
    var listingURL: URL
    /// The provider's licence statement, shown verbatim.
    var rights: String
    var matchScore: Double = 0

    var id: String { downloadURL.absoluteString }
}

struct EbookQuery: Equatable {
    var title: String
    var author: String?
    var isbn: String?

    var mainTitle: String {
        title.split(whereSeparator: { $0 == ":" || $0 == "(" }).first.map { $0.trimmingCharacters(in: .whitespaces) } ?? title
    }
    var surname: String? { author?.split(separator: " ").last.map(String.init) }
}

protocol EbookProvider: Sendable {
    var id: EbookProviderID { get }
    func search(_ query: EbookQuery) async throws -> [EbookEdition]
}

enum EbookMatching {
    /// Keeps editions whose title and author plausibly match the query, best first.
    static func rank(_ editions: [EbookEdition], for query: EbookQuery) -> [EbookEdition] {
        editions.compactMap { e -> EbookEdition? in
            let titleExact = BookMatcher.normalize(e.title) == BookMatcher.normalize(query.mainTitle)
            let titleOK = titleExact || BookMatcher.titlesMatch(e.title, query.mainTitle)
                || BookMatcher.normalize(e.title).contains(BookMatcher.normalize(query.mainTitle)) && query.mainTitle.count >= 5
            guard titleOK else { return nil }
            let authorOK = query.author.map { a in BookMatcher.authorsMatch(claimed: a, actual: e.authors) } ?? true
            guard authorOK else { return nil }
            var copy = e
            copy.matchScore = (titleExact ? 1 : 0.7) + (e.provider == .standardEbooks ? 0.1 : 0)
            return copy
        }
        .sorted { $0.matchScore > $1.matchScore || ($0.matchScore == $1.matchScore && $0.title < $1.title) }
    }
}

private func fetch(_ url: URL) async throws -> Data {
    var req = URLRequest(url: url)
    req.setValue("Folio/1.0 (macOS reading app; user-initiated search)", forHTTPHeaderField: "User-Agent")
    req.timeoutInterval = 30
    let (data, response) = try await URLSession.shared.data(for: req)
    guard (response as? HTTPURLResponse)?.statusCode == 200 else {
        throw URLError(.badServerResponse)
    }
    return data
}

// MARK: - Atom / OPDS parsing (shared)

final class OPDSParser: NSObject, XMLParserDelegate {
    struct Link { var href: String; var type: String; var rel: String; var title: String; var length: Int64? }
    struct Entry {
        var title = ""
        var authors: [String] = []
        var content = ""
        var rights = ""
        var language: String?
        var id = ""
        var links: [Link] = []
    }
    private(set) var entries: [Entry] = []
    private var current: Entry?
    private var text = ""
    private var inAuthor = false

    static func parse(_ data: Data) -> [Entry] {
        let p = OPDSParser()
        let xml = XMLParser(data: data)
        xml.delegate = p
        xml.parse()
        return p.entries
    }

    func parser(_ p: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes a: [String: String]) {
        text = ""
        switch name {
        case "entry": current = Entry()
        case "author": inAuthor = true
        case "link" where current != nil:
            if let href = a["href"] {
                current?.links.append(Link(href: href, type: a["type"] ?? "", rel: a["rel"] ?? "", title: a["title"] ?? "",
                                           length: a["length"].flatMap { Int64($0) }))
            }
        default: break
        }
    }

    func parser(_ p: XMLParser, foundCharacters s: String) { text += s }

    func parser(_ p: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if current != nil {
            switch name {
            case "title" where !inAuthor: current?.title = t
            case "name" where inAuthor: current?.authors.append(t)
            case "content": current?.content = t
            case "rights", "dcterms:rights": current?.rights = t
            case "dcterms:language", "dc:language": current?.language = t
            case "id": current?.id = t
            default: break
            }
        }
        if name == "author" { inAuthor = false }
        if name == "entry", let c = current { entries.append(c); current = nil }
        text = ""
    }
}

private func absolute(_ href: String, base: String) -> URL? {
    href.hasPrefix("http") ? URL(string: href) : URL(string: base + href)
}

// MARK: - Project Gutenberg (official OPDS catalog)

struct GutenbergProvider: EbookProvider {
    let id = EbookProviderID.gutenberg
    static let base = "https://www.gutenberg.org"

    func search(_ query: EbookQuery) async throws -> [EbookEdition] {
        var c = URLComponents(string: "\(Self.base)/ebooks/search.opds/")!
        c.queryItems = [.init(name: "query", value: [query.mainTitle, query.surname].compactMap { $0 }.joined(separator: " "))]
        let candidates = Self.parseSearch(try await fetch(c.url!))
            .filter { BookMatcher.titlesMatch($0.title, query.mainTitle)
                || BookMatcher.normalize($0.title).contains(BookMatcher.normalize(query.mainTitle)) }
            .prefix(4)
        // Each book's own feed carries its rights statement, language and EPUB links with sizes.
        return await withTaskGroup(of: EbookEdition?.self) { group in
            for c in candidates {
                group.addTask { try? Self.parseBook(await fetch(c.feed), bookID: c.bookID) }
            }
            var out: [EbookEdition] = []
            for await e in group { if let e { out.append(e) } }
            return out
        }
    }

    struct Candidate { var title: String; var author: String; var feed: URL; var bookID: String }

    static func parseSearch(_ data: Data) -> [Candidate] {
        OPDSParser.parse(data).compactMap { e in
            guard let link = e.links.first(where: { $0.rel == "subsection" && $0.href.contains("/ebooks/") }),
                  let feed = absolute(link.href, base: base) else { return nil }
            let id = feed.deletingPathExtension().lastPathComponent
            guard Int(id) != nil else { return nil }
            return Candidate(title: e.title, author: e.content, feed: feed, bookID: id)
        }
    }

    /// Builds an edition from a book feed, only if Project Gutenberg states it is in the public domain.
    static func parseBook(_ data: Data, bookID: String) -> EbookEdition? {
        let entries = OPDSParser.parse(data)
        guard let main = entries.first(where: { !$0.rights.isEmpty }), main.rights.localizedCaseInsensitiveContains("public domain") else { return nil }
        let epubs = entries.flatMap(\.links).filter { $0.type == "application/epub+zip" && $0.rel.contains("acquisition") }
        // Prefer the EPUB3 with images unless it is very large; otherwise the lighter "no images" file.
        let rich = epubs.first { $0.href.contains("epub3") && ($0.length ?? 0) < 40_000_000 }
        guard let pick = rich ?? epubs.first(where: { $0.href.contains("noimages") }) ?? epubs.first,
              let url = absolute(pick.href, base: base) else { return nil }
        let authors = entries.flatMap(\.authors).first.map { [GutenbergProvider.displayName($0)] } ?? []
        return EbookEdition(provider: .gutenberg, title: main.title, authors: authors, language: main.language, year: nil,
                            fileSize: pick.length, formatLabel: pick.href.contains("epub3") ? "EPUB 3" : "EPUB",
                            downloadURL: url, listingURL: URL(string: "\(base)/ebooks/\(bookID)")!,
                            rights: "\(main.rights) (Project Gutenberg). If you're outside the USA, check your local laws.")
    }

    /// "Austen, Jane" → "Jane Austen".
    static func displayName(_ name: String) -> String {
        let parts = name.components(separatedBy: ", ")
        guard parts.count >= 2 else { return name }
        return (parts[1...].joined(separator: ", ") + " " + parts[0]).trimmingCharacters(in: .whitespaces)
    }
}

// MARK: - Standard Ebooks (public Atom search feed)

struct StandardEbooksProvider: EbookProvider {
    let id = EbookProviderID.standardEbooks

    func search(_ query: EbookQuery) async throws -> [EbookEdition] {
        var c = URLComponents(string: "https://standardebooks.org/feeds/atom/all")!
        c.queryItems = [.init(name: "query", value: [query.mainTitle, query.surname].compactMap { $0 }.joined(separator: " "))]
        return Self.parse(try await fetch(c.url!))
    }

    static func parse(_ data: Data) -> [EbookEdition] {
        OPDSParser.parse(data).compactMap { e in
            // The recommended "compatible" EPUB, not the advanced, Kobo or Kindle variants. The feed's URL is
            // kept exactly as given: without its query parameter the site serves an HTML page instead of the file.
            guard let epub = e.links.first(where: { $0.rel == "enclosure" && $0.type == "application/epub+zip"
                    && !$0.href.contains("_advanced") && !$0.href.contains(".kepub") }),
                  let url = URL(string: epub.href),
                  let listing = e.links.first(where: { $0.rel == "alternate" }).flatMap({ URL(string: $0.href) }) else { return nil }
            return EbookEdition(provider: .standardEbooks, title: e.title, authors: e.authors, language: "en", year: nil,
                                fileSize: epub.length, formatLabel: "EPUB", downloadURL: url, listingURL: listing,
                                rights: e.rights.isEmpty ? "Public domain in the United States." : e.rights)
        }
    }
}

// MARK: - Search across providers

enum EbookSearch {
    static let providers: [EbookProvider] = [StandardEbooksProvider(), GutenbergProvider()]

    struct Result {
        var editions: [EbookEdition]
        var failedProviders: [EbookProviderID]
    }

    /// Searches every provider in parallel. A provider that fails is reported, not fatal.
    static func find(_ query: EbookQuery, providers: [EbookProvider] = providers) async -> Result {
        var q = query
        if q.title.isEmpty, let isbn = q.isbn, let doc = await OpenLibrary.lookup(isbn: isbn, title: "", author: nil) {
            q.title = doc.title
            q.author = doc.author_name?.first
        }
        let resolved = q
        let outcomes: [(EbookProviderID, [EbookEdition]?)] = await withTaskGroup(of: (EbookProviderID, [EbookEdition]?).self) { group in
            for p in providers { group.addTask { (p.id, try? await p.search(resolved)) } }
            var all: [(EbookProviderID, [EbookEdition]?)] = []
            for await r in group { all.append(r) }
            return all
        }
        var editions = EbookMatching.rank(outcomes.flatMap { $0.1 ?? [] }, for: resolved)
        // Fill in sizes the provider didn't state (Gutenberg) with a HEAD request.
        editions = await withTaskGroup(of: (Int, Int64?).self) { group in
            for (i, e) in editions.enumerated() where e.fileSize == nil {
                group.addTask {
                    var req = URLRequest(url: e.downloadURL)
                    req.httpMethod = "HEAD"
                    req.timeoutInterval = 15
                    let r = try? await URLSession.shared.data(for: req)
                    let len = (r?.1 as? HTTPURLResponse)?.expectedContentLength
                    return (i, len.flatMap { $0 > 0 ? $0 : nil })
                }
            }
            var copy = editions
            for await (i, size) in group { copy[i].fileSize = size }
            return copy
        }
        return Result(editions: editions, failedProviders: outcomes.filter { $0.1 == nil }.map(\.0))
    }
}
