import Foundation

enum GoodreadsCSV {
    struct FormatError: LocalizedError {
        var errorDescription: String? { "This doesn't look like a Goodreads export (no Title column found)." }
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy/MM/dd"
        return f
    }()

    static func rows(_ text: String) -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var inQuotes = false
        let chars = Array(text)
        var i = 0
        while i < chars.count {
            let c = chars[i]
            if inQuotes {
                if c == "\"" {
                    if i + 1 < chars.count, chars[i + 1] == "\"" { field.append("\""); i += 1 } else { inQuotes = false }
                } else {
                    field.append(c)
                }
            } else if c == "\"" {
                inQuotes = true
            } else if c == "," {
                row.append(field); field = ""
            } else if c == "\n" || c == "\r\n" || c == "\r" {
                row.append(field); field = ""
                rows.append(row); row = []
            } else {
                field.append(c)
            }
            i += 1
        }
        if !field.isEmpty || !row.isEmpty { row.append(field); rows.append(row) }
        return rows.filter { !($0.count == 1 && $0[0].isEmpty) }
    }

    static func parse(_ text: String) throws -> [Book] {
        let all = rows(text.hasPrefix("\u{FEFF}") ? String(text.dropFirst()) : text)
        guard let header = all.first, header.contains("Title") else { throw FormatError() }
        let idx = Dictionary(header.enumerated().map { ($1.trimmingCharacters(in: .whitespaces), $0) }, uniquingKeysWith: { a, _ in a })

        func value(_ row: [String], _ col: String) -> String {
            guard let i = idx[col], i < row.count else { return "" }
            return row[i].trimmingCharacters(in: .whitespacesAndNewlines)
        }
        func cleanISBN(_ s: String) -> String? {
            let digits = s.filter { $0.isNumber || $0 == "X" }
            return digits.isEmpty ? nil : digits
        }

        return all.dropFirst().compactMap { row -> Book? in
            let title = value(row, "Title")
            guard !title.isEmpty else { return nil }

            var authors = [value(row, "Author")].filter { !$0.isEmpty }
            authors += value(row, "Additional Authors").split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }

            let exclusive = value(row, "Exclusive Shelf").lowercased()
            let status: ReadingStatus
            switch exclusive {
            case "read": status = .read
            case "currently-reading": status = .reading
            case "to-read": status = .wantToRead
            case let s where s.contains("dnf") || s.contains("did-not-finish") || s.contains("abandon"): status = .dnf
            default: status = .wantToRead
            }

            let shelves = value(row, "Bookshelves").split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty && $0 != exclusive && !["read", "to-read", "currently-reading"].contains($0) }

            let rating = Double(value(row, "My Rating")).flatMap { $0 > 0 ? $0 : nil }
            let pages = Int(value(row, "Number of Pages"))
            let year = Int(value(row, "Original Publication Year")) ?? Int(value(row, "Year Published"))
            let review = value(row, "My Review")
                .replacingOccurrences(of: "<br\\s*/?>", with: "\n", options: .regularExpression)
                .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)

            var book = Book(
                title: title,
                authors: authors,
                isbn: cleanISBN(value(row, "ISBN13")) ?? cleanISBN(value(row, "ISBN")),
                pageCount: pages,
                publishYear: year,
                publisher: value(row, "Publisher").isEmpty ? nil : value(row, "Publisher")
            )
            book.status = status
            book.rating = rating
            book.review = review
            book.tags = shelves
            book.dateAdded = dateFormatter.date(from: value(row, "Date Added")) ?? Date()
            book.dateFinished = status == .read ? dateFormatter.date(from: value(row, "Date Read")) : nil
            book.readCount = Int(value(row, "Read Count")) ?? (status == .read ? 1 : 0)
            if status == .read, let pages { book.currentPage = pages }
            let privateNotes = value(row, "Private Notes")
            if !privateNotes.isEmpty { book.notes = [BookNote(text: privateNotes, isQuote: false)] }
            return book
        }
    }

    static func export(_ books: [Book]) -> String {
        let header = ["Title", "Author", "Additional Authors", "ISBN13", "My Rating", "Number of Pages",
                      "Original Publication Year", "Date Read", "Date Added", "Bookshelves", "Exclusive Shelf",
                      "My Review", "Read Count"]
        func esc(_ s: String) -> String {
            s.contains(where: { ",\"\n".contains($0) }) ? "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\"" : s
        }
        func shelf(_ s: ReadingStatus) -> String {
            switch s {
            case .read: "read"
            case .reading: "currently-reading"
            case .wantToRead: "to-read"
            case .dnf: "did-not-finish"
            }
        }
        var lines = [header.joined(separator: ",")]
        for b in books {
            let fields: [String] = [
                b.title,
                b.authors.first ?? "",
                b.authors.dropFirst().joined(separator: ", "),
                b.isbn ?? "",
                b.rating.map { String(Int($0.rounded())) } ?? "0",
                b.pageCount.map(String.init) ?? "",
                b.publishYear.map(String.init) ?? "",
                b.dateFinished.map { dateFormatter.string(from: $0) } ?? "",
                dateFormatter.string(from: b.dateAdded),
                b.tags.joined(separator: ", "),
                shelf(b.status),
                b.review,
                String(b.readCount),
            ]
            lines.append(fields.map(esc).joined(separator: ","))
        }
        return lines.joined(separator: "\n")
    }
}
