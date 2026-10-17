import Foundation
import SQLite3
@testable import Folio

/// Builds a synthetic Apple Books container (same tables/columns Folio reads, WAL mode like the real store).
enum AppleBooksFixture {
    struct Asset {
        var id: String, title: String, author: String?
        var progress: Double = 0, finished = false, finishedDate: Date? = nil
        var genre: String? = nil, pages: Int = 0, sample = false, hidden = false, contentType = 1
    }
    struct Annotation {
        var uuid: String, asset: String, text: String?, note: String? = nil, chapter: String? = nil
        var type = 2, deleted = false, style = 3, modified: Date = Date(timeIntervalSinceReferenceDate: 700_000_000)
    }

    static func exec(_ db: OpaquePointer?, _ sql: String) {
        var err: UnsafeMutablePointer<CChar>?
        if sqlite3_exec(db, sql, nil, nil, &err) != SQLITE_OK { fatalError(String(cString: err!)) }
    }

    static func q(_ s: String?) -> String { s.map { "'" + $0.replacingOccurrences(of: "'", with: "''") + "'" } ?? "NULL" }

    @discardableResult
    static func make(at root: URL, assets: [Asset], annotations: [Annotation], dropColumn: String? = nil) -> URL {
        let fm = FileManager.default
        try? fm.createDirectory(at: root.appendingPathComponent("BKLibrary"), withIntermediateDirectories: true)
        try? fm.createDirectory(at: root.appendingPathComponent("AEAnnotation"), withIntermediateDirectories: true)

        var lib: OpaquePointer?
        sqlite3_open(root.appendingPathComponent("BKLibrary/BKLibrary-1-091020131601.sqlite").path, &lib)
        exec(lib, "PRAGMA journal_mode=WAL;")
        let libCols = ["Z_PK INTEGER PRIMARY KEY", "ZASSETID VARCHAR", "ZTITLE VARCHAR", "ZAUTHOR VARCHAR", "ZGENRE VARCHAR",
                       "ZBOOKDESCRIPTION VARCHAR", "ZLANGUAGE VARCHAR", "ZYEAR VARCHAR", "ZPAGECOUNT INTEGER", "ZCONTENTTYPE INTEGER",
                       "ZREADINGPROGRESS FLOAT", "ZBOOKHIGHWATERMARKPROGRESS FLOAT", "ZISFINISHED INTEGER", "ZDATEFINISHED TIMESTAMP",
                       "ZCREATIONDATE TIMESTAMP", "ZISSAMPLE INTEGER", "ZISHIDDEN INTEGER", "ZISSTOREAUDIOBOOK INTEGER"]
            .filter { dropColumn == nil || !$0.hasPrefix(dropColumn! + " ") }
        exec(lib, "CREATE TABLE ZBKLIBRARYASSET (\(libCols.joined(separator: ", ")));")
        for (i, a) in assets.enumerated() {
            let finished = a.finishedDate.map { String($0.timeIntervalSinceReferenceDate) } ?? "NULL"
            var cols = ["Z_PK", "ZASSETID", "ZTITLE", "ZAUTHOR", "ZGENRE", "ZPAGECOUNT", "ZCONTENTTYPE", "ZREADINGPROGRESS",
                        "ZBOOKHIGHWATERMARKPROGRESS", "ZISFINISHED", "ZDATEFINISHED", "ZCREATIONDATE", "ZISSAMPLE", "ZISHIDDEN"]
            var vals = ["\(i + 1)", q(a.id), q(a.title), q(a.author), q(a.genre), "\(a.pages)", "\(a.contentType)", "\(a.progress)",
                        "\(a.progress)", a.finished ? "1" : "0", finished, "700000000", a.sample ? "1" : "0", a.hidden ? "1" : "0"]
            if let drop = dropColumn, let idx = cols.firstIndex(of: drop) { cols.remove(at: idx); vals.remove(at: idx) }
            exec(lib, "INSERT INTO ZBKLIBRARYASSET (\(cols.joined(separator: ","))) VALUES (\(vals.joined(separator: ",")));")
        }
        sqlite3_close(lib)

        var ann: OpaquePointer?
        sqlite3_open(root.appendingPathComponent("AEAnnotation/AEAnnotation_v10312011_1727_local.sqlite").path, &ann)
        exec(ann, "PRAGMA journal_mode=WAL;")
        exec(ann, """
        CREATE TABLE ZAEANNOTATION (Z_PK INTEGER PRIMARY KEY, ZANNOTATIONDELETED INTEGER, ZANNOTATIONSTYLE INTEGER, ZANNOTATIONTYPE INTEGER,
          ZANNOTATIONCREATIONDATE TIMESTAMP, ZANNOTATIONMODIFICATIONDATE TIMESTAMP, ZANNOTATIONASSETID VARCHAR, ZANNOTATIONLOCATION VARCHAR,
          ZANNOTATIONNOTE VARCHAR, ZANNOTATIONSELECTEDTEXT VARCHAR, ZANNOTATIONUUID VARCHAR, ZFUTUREPROOFING5 VARCHAR);
        """)
        for (i, a) in annotations.enumerated() {
            exec(ann, """
            INSERT INTO ZAEANNOTATION VALUES (\(i + 1), \(a.deleted ? 1 : 0), \(a.style), \(a.type), 690000000, \(a.modified.timeIntervalSinceReferenceDate),
              \(q(a.asset)), 'epubcfi(/6/14[ch\(i)]!/4/2/1:0)', \(q(a.note)), \(q(a.text)), \(q(a.uuid)), \(q(a.chapter)));
            """)
        }
        sqlite3_close(ann)
        return root
    }

    /// Clearly labelled sample data used for tests and README screenshots.
    static let sampleAssets: [Asset] = [
        Asset(id: "SAMPLE-A1", title: "Meditations", author: "Marcus Aurelius", progress: 0.42, genre: "Philosophy"),
        Asset(id: "SAMPLE-A2", title: "The Odyssey", author: "Homer", progress: 1, finished: true,
              finishedDate: Date(timeIntervalSinceReferenceDate: 780_000_000), genre: "Classics"),
        Asset(id: "SAMPLE-A3", title: "Walden", author: "Henry David Thoreau", genre: "Nature"),
        Asset(id: "SAMPLE-A4", title: "A Sample Chapter", author: "Someone", sample: true),
    ]
    static let sampleAnnotations: [Annotation] = [
        Annotation(uuid: "ANN-1", asset: "SAMPLE-A1", text: "The happiness of your life depends upon the quality of your thoughts.", chapter: "Book Five"),
        Annotation(uuid: "ANN-2", asset: "SAMPLE-A1", text: "Waste no more time arguing about what a good man should be. Be one.",
                   note: "Sample note: action over debate.", chapter: "Book Ten"),
        Annotation(uuid: "ANN-3", asset: "SAMPLE-A2", text: "Tell me, O Muse, of that ingenious hero.", chapter: "Book I"),
        Annotation(uuid: "ANN-4", asset: "SAMPLE-A3", text: "A deleted highlight", deleted: true),
        Annotation(uuid: "ANN-5", asset: "MISSING-ASSET", text: "Highlight for a book removed from Apple Books"),
        Annotation(uuid: "POS-1", asset: "SAMPLE-A1", text: nil, type: 3),
    ]
}
