import Foundation
import SQLite3

/// A book as recorded in Apple Books' library database (`ZBKLIBRARYASSET`).
struct ABBook: Hashable {
    var assetID: String
    var title: String
    var author: String?
    var genre: String?
    var description: String?
    var language: String?
    var year: Int?
    var pageCount: Int?
    /// 1 = book (EPUB/iBooks), 3 = PDF in observed data.
    var contentType: Int?
    var readingProgress: Double?
    var highWatermark: Double?
    var isFinished: Bool
    var dateFinished: Date?
    var addedDate: Date?
    var isSample: Bool
    var isHidden: Bool
    var isAudiobook: Bool
}

/// A highlight or note from Apple Books' annotation database (`ZAEANNOTATION`).
struct ABAnnotation: Hashable {
    var uuid: String
    var assetID: String
    var selectedText: String?
    var note: String?
    var chapter: String?
    var location: String?
    var style: Int?
    var type: Int
    var isDeleted: Bool
    var created: Date?
    var modified: Date?

    /// Type 2 rows with text are highlights (verified on Books 7.6). Type 3 rows hold reading positions.
    var isHighlight: Bool { type == 2 && !(selectedText ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
}

enum AppleBooksError: LocalizedError, Equatable {
    case notInstalled
    case databaseMissing(String)
    case permissionDenied(String)
    case schemaUnsupported(missing: [String])
    case unreadable(String)

    var errorDescription: String? {
        switch self {
        case .notInstalled: "Apple Books data wasn't found on this Mac."
        case .databaseMissing(let which): "The Apple Books \(which) database wasn't found. It may still be syncing from iCloud."
        case .permissionDenied: "macOS blocked access to Apple Books data. Allow Folio in System Settings › Privacy & Security."
        case .schemaUnsupported(let missing): "This version of Apple Books stores data differently (missing \(missing.joined(separator: ", "))). Nothing was changed."
        case .unreadable(let m): "Apple Books data couldn't be read: \(m)"
        }
    }
}

/// Reads Apple Books' databases without ever opening Apple's files: each sync copies the database
/// together with its write-ahead log into Folio's cache and reads only that snapshot.
struct AppleBooksReader {
    /// `~/Library/Containers/com.apple.iBooksX/Data/Documents`, or an override for tests and demos.
    var documentsURL: URL
    var snapshotRoot: URL

    static func defaultDocumentsURL() -> URL {
        if let override = ProcessInfo.processInfo.environment["FOLIO_APPLE_BOOKS_DIR"] {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Containers/com.apple.iBooksX/Data/Documents", isDirectory: true)
    }

    static let libraryColumns = ["ZASSETID", "ZTITLE", "ZAUTHOR", "ZREADINGPROGRESS", "ZISFINISHED", "ZDATEFINISHED"]
    static let annotationColumns = ["ZANNOTATIONUUID", "ZANNOTATIONASSETID", "ZANNOTATIONSELECTEDTEXT", "ZANNOTATIONTYPE", "ZANNOTATIONDELETED"]

    var libraryFolder: URL { documentsURL.appendingPathComponent("BKLibrary", isDirectory: true) }
    var annotationFolder: URL { documentsURL.appendingPathComponent("AEAnnotation", isDirectory: true) }

    /// The main database file in a folder, e.g. `BKLibrary-1-091020131601.sqlite`.
    func database(in folder: URL, prefix: String) throws -> URL {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: documentsURL.path, isDirectory: &isDir), isDir.boolValue else { throw AppleBooksError.notInstalled }
        let names: [String]
        do { names = try fm.contentsOfDirectory(atPath: folder.path) } catch {
            let ns = error as NSError
            if ns.code == NSFileReadNoPermissionError || (ns.underlyingErrors.first as NSError?)?.code == Int(EPERM) {
                throw AppleBooksError.permissionDenied(folder.path)
            }
            throw AppleBooksError.databaseMissing(prefix)
        }
        guard let name = names.filter({ $0.hasPrefix(prefix) && $0.hasSuffix(".sqlite") }).sorted().last else {
            throw AppleBooksError.databaseMissing(prefix)
        }
        return folder.appendingPathComponent(name)
    }

    /// Size and modification time of the database files, used to skip syncs when nothing changed.
    func fingerprint() -> String {
        var parts: [String] = []
        for (folder, prefix) in [(libraryFolder, "BKLibrary"), (annotationFolder, "AEAnnotation")] {
            guard let db = try? database(in: folder, prefix: prefix) else { parts.append("missing-\(prefix)"); continue }
            for suffix in ["", "-wal"] {
                let attrs = try? FileManager.default.attributesOfItem(atPath: db.path + suffix)
                let size = (attrs?[.size] as? NSNumber)?.int64Value ?? -1
                let mod = (attrs?[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
                parts.append("\(db.lastPathComponent)\(suffix):\(size):\(Int(mod))")
            }
        }
        return parts.joined(separator: "|")
    }

    /// Copies the database, WAL and shared-memory files into a fresh snapshot folder.
    func snapshot(_ db: URL) throws -> URL {
        let fm = FileManager.default
        let dir = snapshotRoot.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let target = dir.appendingPathComponent(db.lastPathComponent)
        do {
            try fm.copyItem(at: db, to: target)
        } catch {
            let ns = error as NSError
            if ns.code == NSFileReadNoPermissionError { throw AppleBooksError.permissionDenied(db.path) }
            throw AppleBooksError.unreadable(error.localizedDescription)
        }
        for suffix in ["-wal", "-shm"] where fm.fileExists(atPath: db.path + suffix) {
            try? fm.copyItem(atPath: db.path + suffix, toPath: target.path + suffix)
        }
        return target
    }

    func cleanSnapshots() {
        try? FileManager.default.removeItem(at: snapshotRoot)
    }

    // MARK: Reading

    func read() throws -> (books: [ABBook], annotations: [ABAnnotation], annotationsAvailable: Bool) {
        defer { cleanSnapshots() }
        let libDB = try snapshot(try database(in: libraryFolder, prefix: "BKLibrary"))
        let books = try SQLiteSnapshot(path: libDB).use { db in
            try db.require(table: "ZBKLIBRARYASSET", columns: Self.libraryColumns)
            return try Self.readBooks(db)
        }
        // Annotations are optional: a missing or changed annotation store must not block book sync.
        guard let annURL = try? database(in: annotationFolder, prefix: "AEAnnotation") else { return (books, [], false) }
        let annDB = try snapshot(annURL)
        let annotations: [ABAnnotation]? = try? SQLiteSnapshot(path: annDB).use { db in
            try db.require(table: "ZAEANNOTATION", columns: Self.annotationColumns)
            return try Self.readAnnotations(db)
        }
        return (books, annotations ?? [], annotations != nil)
    }

    static func coreDataDate(_ v: Double?) -> Date? {
        guard let v, v > 0 else { return nil }
        return Date(timeIntervalSinceReferenceDate: v)
    }

    static func readBooks(_ db: SQLiteSnapshot) throws -> [ABBook] {
        let cols = db.columns(of: "ZBKLIBRARYASSET")
        func col(_ name: String) -> String { cols.contains(name) ? name : "NULL" }
        let sql = """
        SELECT ZASSETID, ZTITLE, ZAUTHOR, \(col("ZGENRE")), \(col("ZBOOKDESCRIPTION")), \(col("ZLANGUAGE")), \(col("ZYEAR")),
               \(col("ZPAGECOUNT")), \(col("ZCONTENTTYPE")), ZREADINGPROGRESS, \(col("ZBOOKHIGHWATERMARKPROGRESS")),
               ZISFINISHED, ZDATEFINISHED, \(col("ZCREATIONDATE")), \(col("ZISSAMPLE")), \(col("ZISHIDDEN")), \(col("ZISSTOREAUDIOBOOK"))
        FROM ZBKLIBRARYASSET
        """
        return try db.rows(sql) { r in
            guard let id = r.string(0), let title = r.string(1), !title.isEmpty else { return nil }
            return ABBook(assetID: id, title: title, author: r.string(2), genre: r.string(3), description: r.string(4),
                          language: r.string(5), year: r.string(6).flatMap { Int($0.prefix(4)) } ?? r.int(6).flatMap { $0 > 0 ? $0 : nil },
                          pageCount: r.int(7).flatMap { $0 > 0 ? $0 : nil }, contentType: r.int(8),
                          readingProgress: r.double(9), highWatermark: r.double(10), isFinished: r.int(11) == 1,
                          dateFinished: coreDataDate(r.double(12)), addedDate: coreDataDate(r.double(13)),
                          isSample: r.int(14) == 1, isHidden: r.int(15) == 1, isAudiobook: r.int(16) == 1)
        }
    }

    static func readAnnotations(_ db: SQLiteSnapshot) throws -> [ABAnnotation] {
        let cols = db.columns(of: "ZAEANNOTATION")
        func col(_ name: String) -> String { cols.contains(name) ? name : "NULL" }
        let sql = """
        SELECT ZANNOTATIONUUID, ZANNOTATIONASSETID, ZANNOTATIONSELECTEDTEXT, \(col("ZANNOTATIONNOTE")), \(col("ZFUTUREPROOFING5")),
               \(col("ZANNOTATIONLOCATION")), \(col("ZANNOTATIONSTYLE")), ZANNOTATIONTYPE, ZANNOTATIONDELETED,
               \(col("ZANNOTATIONCREATIONDATE")), \(col("ZANNOTATIONMODIFICATIONDATE"))
        FROM ZAEANNOTATION
        """
        return try db.rows(sql) { r in
            guard let uuid = r.string(0), let asset = r.string(1) else { return nil }
            return ABAnnotation(uuid: uuid, assetID: asset, selectedText: r.string(2), note: r.string(3), chapter: r.string(4),
                                location: r.string(5), style: r.int(6), type: r.int(7) ?? -1, isDeleted: r.int(8) == 1,
                                created: coreDataDate(r.double(9)), modified: coreDataDate(r.double(10)))
        }
    }
}

/// Minimal read-only SQLite wrapper over a snapshot copy.
final class SQLiteSnapshot {
    private var handle: OpaquePointer?

    init(path: URL) throws {
        // This is Folio's private snapshot copy; Apple's files are never opened. It is opened read-write because
        // a read-only connection can't open a WAL-mode database whose -shm file is absent (e.g. after Apple Books
        // checkpoints), and `query_only` guarantees no statement can modify it.
        guard sqlite3_open_v2(path.path, &handle, SQLITE_OPEN_READWRITE, nil) == SQLITE_OK else {
            let message = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "open failed"
            sqlite3_close(handle)
            throw AppleBooksError.unreadable(message)
        }
        sqlite3_exec(handle, "PRAGMA query_only = 1;", nil, nil, nil)
    }

    deinit { sqlite3_close(handle) }

    func use<T>(_ body: (SQLiteSnapshot) throws -> T) throws -> T { try body(self) }

    func columns(of table: String) -> Set<String> {
        (try? tableColumns(table)) ?? []
    }

    /// Throws on read errors so they're never mistaken for a schema change.
    func tableColumns(_ table: String) throws -> Set<String> {
        Set(try rows("SELECT name FROM pragma_table_info('\(table)')") { $0.string(0) })
    }

    func require(table: String, columns required: [String]) throws {
        let have = try tableColumns(table)
        guard !have.isEmpty else { throw AppleBooksError.schemaUnsupported(missing: [table]) }
        let missing = required.filter { !have.contains($0) }
        if !missing.isEmpty { throw AppleBooksError.schemaUnsupported(missing: missing) }
    }

    struct Row {
        let stmt: OpaquePointer
        func string(_ i: Int32) -> String? {
            guard sqlite3_column_type(stmt, i) != SQLITE_NULL, let c = sqlite3_column_text(stmt, i) else { return nil }
            return String(cString: c)
        }
        func int(_ i: Int32) -> Int? {
            sqlite3_column_type(stmt, i) == SQLITE_NULL ? nil : Int(sqlite3_column_int64(stmt, i))
        }
        func double(_ i: Int32) -> Double? {
            sqlite3_column_type(stmt, i) == SQLITE_NULL ? nil : sqlite3_column_double(stmt, i)
        }
    }

    func rows<T>(_ sql: String, _ map: (Row) throws -> T?) throws -> [T] {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else {
            throw AppleBooksError.unreadable(String(cString: sqlite3_errmsg(handle)))
        }
        defer { sqlite3_finalize(stmt) }
        var out: [T] = []
        while true {
            let rc = sqlite3_step(stmt)
            if rc == SQLITE_DONE { break }
            guard rc == SQLITE_ROW else { throw AppleBooksError.unreadable(String(cString: sqlite3_errmsg(handle))) }
            if let v = try map(Row(stmt: stmt)) { out.append(v) }
        }
        return out
    }
}
