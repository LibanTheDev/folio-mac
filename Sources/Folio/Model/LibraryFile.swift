import Foundation

/// On-disk representation of the whole library.
struct LibraryFile: Codable {
    static let currentVersion = 2

    var version: Int = LibraryFile.currentVersion
    var books: [Book] = []
    var goals: [Int: Int] = [:]
    /// Tag names that exist even before any book carries them.
    var tagNames: [String] = []
    var shelves: [Shelf] = []
    var sessions: [ReadingSession] = []
    var activeSession: ActiveSession?
    /// Open Library work keys (or "title|author") the user dismissed from recommendations.
    var dismissedRecommendations: [String] = []
    /// Topics the user said they care about, used by discovery.
    var interests: [String] = []

    init() {}

    private enum CodingKeys: String, CodingKey {
        case version, books, goals, tagNames, shelves, sessions, activeSession, dismissedRecommendations, interests
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = c.value(.version, 1)
        books = try c.decode([Book].self, forKey: .books)
        goals = c.value(.goals, [:])
        if version < 2 {
            // v1 stored empty tag names under "shelves" as [String].
            tagNames = c.value(.shelves, [String]())
            shelves = []
        } else {
            tagNames = c.value(.tagNames, [])
            shelves = c.value(.shelves, [])
        }
        sessions = c.value(.sessions, [])
        activeSession = c.value(.activeSession, nil)
        dismissedRecommendations = c.value(.dismissedRecommendations, [])
        interests = c.value(.interests, [])
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(LibraryFile.currentVersion, forKey: .version)
        try c.encode(books, forKey: .books)
        try c.encode(goals, forKey: .goals)
        try c.encode(tagNames, forKey: .tagNames)
        try c.encode(shelves, forKey: .shelves)
        try c.encode(sessions, forKey: .sessions)
        try c.encodeIfPresent(activeSession, forKey: .activeSession)
        try c.encode(dismissedRecommendations, forKey: .dismissedRecommendations)
        try c.encode(interests, forKey: .interests)
    }
}

/// Reads, migrates, writes and backs up the library file.
struct LibraryStore {
    let directory: URL
    var fileURL: URL { directory.appendingPathComponent("library.json") }
    var backupsURL: URL { directory.appendingPathComponent("Backups", isDirectory: true) }

    /// ISO-8601 with fractional seconds; also reads plain ISO-8601 written by older versions.
    static func decoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .custom { decoder in
            let c = try decoder.singleValueContainer()
            let s = try c.decode(String.self)
            if let date = fractional.date(from: s) ?? plain.date(from: s) { return date }
            throw DecodingError.dataCorruptedError(in: c, debugDescription: "Invalid date: \(s)")
        }
        return d
    }

    static func encoder() -> JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .custom { date, encoder in
            var c = encoder.singleValueContainer()
            try c.encode(fractional.string(from: date))
        }
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }

    nonisolated(unsafe) private static let fractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    nonisolated(unsafe) private static let plain = ISO8601DateFormatter()

    static func decode(_ data: Data) throws -> LibraryFile {
        try decoder().decode(LibraryFile.self, from: data)
    }

    enum LoadResult {
        case empty
        case loaded(LibraryFile, migratedFrom: Int?)
    }

    /// Loads the library. Before migrating an older schema, the original file is copied to Backups.
    /// A file that can't be decoded is never overwritten: it is moved aside and reported.
    func load() throws -> LoadResult {
        guard let data = try? Data(contentsOf: fileURL) else { return .empty }
        let file: LibraryFile
        do {
            file = try Self.decode(data)
        } catch {
            try? FileManager.default.createDirectory(at: backupsURL, withIntermediateDirectories: true)
            let aside = backupsURL.appendingPathComponent("library.unreadable-\(Self.stamp()).json")
            try? FileManager.default.copyItem(at: fileURL, to: aside)
            throw error
        }
        let raw = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["version"] as? Int ?? 1
        if raw < LibraryFile.currentVersion {
            try backup(data, label: "pre-migration-v\(raw)")
            return .loaded(file, migratedFrom: raw)
        }
        return .loaded(file, migratedFrom: nil)
    }

    func save(_ file: LibraryFile) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try Self.encoder().encode(file)
        try data.write(to: fileURL, options: .atomic)
    }

    /// Writes a dated copy into Backups and prunes old automatic backups.
    func backup(_ data: Data, label: String) throws {
        try FileManager.default.createDirectory(at: backupsURL, withIntermediateDirectories: true)
        try data.write(to: backupsURL.appendingPathComponent("library.\(label)-\(Self.stamp()).json"), options: .atomic)
    }

    /// Keeps one automatic backup per day, retaining the most recent `keep`.
    func dailyBackupIfNeeded(keep: Int = 14) {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        let fm = FileManager.default
        try? fm.createDirectory(at: backupsURL, withIntermediateDirectories: true)
        let day = Self.dayStamp()
        let name = "library.daily-\(day).json"
        let target = backupsURL.appendingPathComponent(name)
        if !fm.fileExists(atPath: target.path) { try? data.write(to: target, options: .atomic) }
        let dailies = ((try? fm.contentsOfDirectory(atPath: backupsURL.path)) ?? [])
            .filter { $0.hasPrefix("library.daily-") }
            .sorted(by: >)
        for old in dailies.dropFirst(keep) { try? fm.removeItem(at: backupsURL.appendingPathComponent(old)) }
    }

    static func stamp() -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyyMMdd-HHmmss"
        return f.string(from: Date())
    }

    static func dayStamp() -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: Date())
    }
}
