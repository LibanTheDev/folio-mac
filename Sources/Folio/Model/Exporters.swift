import Foundation

/// Plain-text exports so the reader always owns their data.
enum MarkdownExporter {
    static func filename(for book: Book) -> String {
        let base = "\(book.title) - \(book.authors.first ?? "Unknown")"
        let cleaned = base.components(separatedBy: CharacterSet(charactersIn: "/\\:*?\"<>|\n\r")).joined(separator: "-")
        return String(cleaned.prefix(120)).trimmingCharacters(in: .whitespaces) + ".md"
    }

    private static func yaml(_ s: String) -> String {
        "\"" + s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }

    /// One Markdown document per book: YAML front matter, review, then notes grouped by type.
    static func markdown(for b: Book, linkTitle: (UUID) -> String? = { _ in nil }) -> String {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withFullDate]
        var front: [String] = ["title: \(yaml(b.title))", "authors: [\(b.authors.map(yaml).joined(separator: ", "))]",
                               "status: \(b.status.rawValue)"]
        if let r = b.rating { front.append("rating: \(r)") }
        if let isbn = b.isbn { front.append("isbn: \(yaml(isbn))") }
        if let y = b.publishYear { front.append("published: \(y)") }
        if let d = b.dateStarted { front.append("started: \(iso.string(from: d))") }
        if let d = b.dateFinished { front.append("finished: \(iso.string(from: d))") }
        if !b.tags.isEmpty { front.append("tags: [\(b.tags.map(yaml).joined(separator: ", "))]") }

        var out = "---\n" + front.joined(separator: "\n") + "\n---\n\n# \(b.title)\n\n*\(b.authorLine)*\n"
        if !b.review.isEmpty { out += "\n## My Review\n\n\(b.review)\n" }
        if b.history.count > 0 {
            out += "\n## Reading History\n\n"
            for t in b.allReadThroughs {
                out += "- \(t.started.map { iso.string(from: $0) } ?? "?") → \(t.finished.map { iso.string(from: $0) } ?? "in progress")"
                    + (t.outcome == .abandoned ? " (stopped)" : "") + "\n"
            }
        }
        for kind in BookNote.Kind.allCases {
            let notes = b.notes.filter { $0.kind == kind }.sorted { ($0.page ?? Int.max, $0.created) < ($1.page ?? Int.max, $1.created) }
            guard !notes.isEmpty else { continue }
            out += "\n## \(kind.plural)\n"
            for n in notes {
                let body = kind.isFromBook
                    ? n.text.components(separatedBy: "\n").map { "> \($0)" }.joined(separator: "\n")
                    : n.text
                out += "\n\(body)\n"
                var meta: [String] = []
                if let loc = n.locationLabel { meta.append(loc) }
                if !n.tags.isEmpty { meta.append(n.tags.map { "#\($0)" }.joined(separator: " ")) }
                let links = n.links.compactMap(linkTitle)
                if !links.isEmpty { meta.append("Connected to: " + links.map { "[[\($0)]]" }.joined(separator: ", ")) }
                if !meta.isEmpty { out += "\n— " + meta.joined(separator: " · ") + "\n" }
            }
        }
        return out
    }
}

enum SessionsCSV {
    static func export(_ sessions: [ReadingSession], books: [Book]) -> String {
        let byID = Dictionary(uniqueKeysWithValues: books.map { ($0.id, $0) })
        let iso = ISO8601DateFormatter()
        func esc(_ s: String) -> String { s.contains(where: { ",\"\n".contains($0) }) ? "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\"" : s }
        var lines = ["Book,Author,Start,Minutes,Start Page,End Page,Pages,Manual"]
        for s in sessions.sorted(by: { $0.start < $1.start }) {
            let b = byID[s.bookID]
            lines.append([esc(b?.title ?? "Deleted book"), esc(b?.authorLine ?? ""), iso.string(from: s.start),
                          String(format: "%.1f", s.duration / 60), s.startPage.map(String.init) ?? "",
                          s.endPage.map(String.init) ?? "", String(s.pagesRead), s.isManual ? "yes" : "no"].joined(separator: ","))
        }
        return lines.joined(separator: "\n")
    }
}

/// Optional off-Mac safety copies in iCloud Drive (plain files; no entitlement required).
enum CloudBackup {
    static var folder: URL? {
        let drive = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs", isDirectory: true)
        guard FileManager.default.fileExists(atPath: drive.path) else { return nil }
        return drive.appendingPathComponent("Folio Backups", isDirectory: true)
    }

    static var isAvailable: Bool { folder != nil }

    /// Writes today's snapshot (once per day) and keeps the newest `keep` snapshots.
    @discardableResult
    static func backup(_ data: Data, keep: Int = 30, now: Date = Date(), to destination: URL? = nil) throws -> URL? {
        guard let folder = destination ?? folder else { return nil }
        let fm = FileManager.default
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        let target = folder.appendingPathComponent("Folio \(f.string(from: now)).folio.json")
        try data.write(to: target, options: .atomic)
        let snapshots = ((try? fm.contentsOfDirectory(atPath: folder.path)) ?? []).filter { $0.hasSuffix(".folio.json") }.sorted(by: >)
        for old in snapshots.dropFirst(keep) { try? fm.removeItem(at: folder.appendingPathComponent(old)) }
        return target
    }
}
