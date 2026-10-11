import CryptoKit
import Foundation
import Testing
@testable import Folio

func tempDir(_ name: String) -> URL {
    let u = FileManager.default.temporaryDirectory.appendingPathComponent("\(name)-\(UUID().uuidString)", isDirectory: true)
    try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
    return u
}

/// SHA-256 and modification date of every file under a folder.
func fileState(_ root: URL) -> [String: String] {
    var out: [String: String] = [:]
    let e = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.contentModificationDateKey])
    while let u = e?.nextObject() as? URL {
        guard let data = try? Data(contentsOf: u) else { continue }
        let mod = (try? u.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)?.timeIntervalSince1970 ?? 0
        out[u.lastPathComponent] = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() + "@\(mod)"
    }
    return out
}

@Suite struct AppleBooksReaderTests {
    @Test func readsSnapshotWithoutTouchingSourceFiles() throws {
        let root = AppleBooksFixture.make(at: tempDir("ab-src"), assets: AppleBooksFixture.sampleAssets, annotations: AppleBooksFixture.sampleAnnotations)
        let before = fileState(root)
        let snaps = tempDir("ab-snap")
        let reader = AppleBooksReader(documentsURL: root, snapshotRoot: snaps)
        let r = try reader.read()
        #expect(r.books.count == 4)
        #expect(r.annotations.count == 6)
        #expect(r.annotationsAvailable)
        let meditations = try #require(r.books.first { $0.assetID == "SAMPLE-A1" })
        #expect(abs((meditations.readingProgress ?? 0) - 0.42) < 1e-9)
        #expect(meditations.pageCount == nil)   // 0 means unknown
        let odyssey = try #require(r.books.first { $0.assetID == "SAMPLE-A2" })
        #expect(odyssey.isFinished && odyssey.dateFinished == Date(timeIntervalSinceReferenceDate: 780_000_000))
        #expect(fileState(root) == before)       // Apple's files are byte-for-byte unchanged
        #expect(!FileManager.default.fileExists(atPath: snaps.path))  // snapshots cleaned up
    }

    @Test func schemaChangeIsReportedAndNothingRead() {
        let root = AppleBooksFixture.make(at: tempDir("ab-schema"), assets: AppleBooksFixture.sampleAssets, annotations: [],
                                          dropColumn: "ZREADINGPROGRESS")
        let reader = AppleBooksReader(documentsURL: root, snapshotRoot: tempDir("ab-snap"))
        #expect(throws: AppleBooksError.schemaUnsupported(missing: ["ZREADINGPROGRESS"])) { try reader.read() }
    }

    @Test func missingStoresAreReportedNotFatal() throws {
        let empty = tempDir("ab-empty")
        let reader = AppleBooksReader(documentsURL: empty, snapshotRoot: tempDir("ab-snap"))
        #expect(throws: AppleBooksError.databaseMissing("BKLibrary")) { try reader.read() }
        let nowhere = AppleBooksReader(documentsURL: empty.appendingPathComponent("nope"), snapshotRoot: tempDir("ab-snap"))
        #expect(throws: AppleBooksError.notInstalled) { try nowhere.read() }

        // Annotation store missing: books still sync.
        let root = AppleBooksFixture.make(at: tempDir("ab-noann"), assets: AppleBooksFixture.sampleAssets, annotations: [])
        try FileManager.default.removeItem(at: root.appendingPathComponent("AEAnnotation"))
        let r = try AppleBooksReader(documentsURL: root, snapshotRoot: tempDir("ab-snap")).read()
        #expect(r.books.count == 4 && !r.annotationsAvailable)
    }

    @Test func fingerprintChangesWhenWALChanges() throws {
        let root = AppleBooksFixture.make(at: tempDir("ab-fp"), assets: AppleBooksFixture.sampleAssets, annotations: [])
        let reader = AppleBooksReader(documentsURL: root, snapshotRoot: tempDir("ab-snap"))
        let a = reader.fingerprint()
        #expect(a == reader.fingerprint())
        let wal = root.appendingPathComponent("BKLibrary/BKLibrary-1-091020131601.sqlite-wal")
        if FileManager.default.fileExists(atPath: wal.path) {
            try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(120)], ofItemAtPath: wal.path)
        } else {
            try Data("x".utf8).write(to: wal)
        }
        #expect(a != reader.fingerprint())
    }
}

@MainActor @Suite struct AppleBooksMergeTests {
    func library() -> Library { Library(directory: tempDir("ab-lib"), autosave: false) }

    func snapshot() throws -> (books: [ABBook], annotations: [ABAnnotation], annotationsAvailable: Bool) {
        let root = AppleBooksFixture.make(at: tempDir("ab-m"), assets: AppleBooksFixture.sampleAssets, annotations: AppleBooksFixture.sampleAnnotations)
        return try AppleBooksReader(documentsURL: root, snapshotRoot: tempDir("ab-snap")).read()
    }

    @Test func importsBooksProgressAndHighlightsWithAttribution() throws {
        let lib = library()
        let snap = try snapshot()
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let s = lib.mergeAppleBooks(books: snap.books, annotations: snap.annotations, now: now)
        #expect(s.booksAdded == 3 && s.skippedSamplesOrHidden == 1)
        let med = try #require(lib.books.first { $0.title == "Meditations" })
        #expect(med.status == .reading && med.dateStarted == nil)            // start date not invented
        #expect(med.progressProvenance == .confirmedByAppleBooks && abs(med.progress - 0.42) < 1e-9)
        #expect(med.notes.filter { $0.kind == .highlight }.count == 2)
        let note = try #require(med.notes.first { $0.kind == .reflection })
        #expect(note.text == "Sample note: action over debate." && note.links.count == 1)
        #expect(med.notes.allSatisfy { $0.source?.kind == .appleBooks })
        #expect(med.notes.first { $0.source?.externalID == "ANN-1" }?.chapter == "Book Five")
        let odyssey = try #require(lib.books.first { $0.title == "The Odyssey" })
        #expect(odyssey.status == .read && odyssey.dateFinished == Date(timeIntervalSinceReferenceDate: 780_000_000))
        let walden = try #require(lib.books.first { $0.title == "Walden" })
        #expect(walden.status == .wantToRead && walden.progressProvenance == .unknown && walden.notes.isEmpty)  // deleted highlight skipped
        #expect(s.highlightsUnmatched == 1)
        #expect(lib.sessions.isEmpty && lib.books.allSatisfy { $0.progressLog.isEmpty })  // no fabricated activity
    }

    @Test func secondSyncIsIdempotent() throws {
        let lib = library()
        let snap = try snapshot()
        lib.mergeAppleBooks(books: snap.books, annotations: snap.annotations, now: Date(timeIntervalSince1970: 1_800_000_000))
        let before = lib.books
        let s = lib.mergeAppleBooks(books: snap.books, annotations: snap.annotations, now: Date(timeIntervalSince1970: 1_800_009_999))
        #expect(lib.books == before)
        #expect(s.booksAdded == 0 && s.highlightsAdded == 0 && s.highlightsUpdated == 0 && s.statusUpgraded == 0)
    }

    @Test func existingFolioBookIsLinkedAndUserDataPreserved() throws {
        let lib = library()
        var mine = Book(title: "Meditations: A New Translation", authors: ["Marcus Aurelius"])
        mine.rating = 5
        mine.review = "My review"
        mine.notes = [BookNote(kind: .reflection, text: "My own note")]
        mine.status = .read
        mine.dateFinished = Date(timeIntervalSince1970: 1_000)
        lib.books = [mine]
        lib.shelves = [Shelf(name: "Stoics", bookIDs: [mine.id])]
        let snap = try snapshot()
        let s = lib.mergeAppleBooks(books: snap.books, annotations: snap.annotations)
        #expect(s.booksLinked == 1 && s.booksAdded == 2)
        let linked = try #require(lib.book(mine.id))
        #expect(linked.appleBooksID == "SAMPLE-A1")
        #expect(linked.rating == 5 && linked.review == "My review" && linked.status == .read)   // never downgraded to reading
        #expect(linked.dateFinished == Date(timeIntervalSince1970: 1_000))
        #expect(linked.notes.contains { $0.text == "My own note" && $0.source == nil })
        #expect(lib.shelves[0].bookIDs == [mine.id])
    }

    @Test func localEditsSurviveAndDeletionsRespectThem() throws {
        let lib = library()
        let snap = try snapshot()
        lib.mergeAppleBooks(books: snap.books, annotations: snap.annotations)
        let medID = try #require(lib.books.first { $0.title == "Meditations" }).id
        let ann1 = try #require(lib.book(medID)?.notes.first { $0.source?.externalID == "ANN-1" })
        let ann2 = try #require(lib.book(medID)?.notes.first { $0.source?.externalID == "ANN-2" })
        lib.updateNote(ann1.id) { $0.text = "Edited in Folio" }
        lib.updateNote(ann2.id) { $0.tags = ["stoicism"] }

        // Apple Books changes ANN-1's text, and deletes ANN-2 and its note.
        var anns = snap.annotations
        anns[0].selectedText = "Apple-side edit"
        anns[1].isDeleted = true
        let s = lib.mergeAppleBooks(books: snap.books, annotations: anns)
        let med = try #require(lib.book(medID))
        #expect(med.notes.first { $0.id == ann1.id }?.text == "Edited in Folio")   // local edit wins
        #expect(med.notes.contains { $0.id == ann2.id })                           // tagged in Folio, so kept
        #expect(!med.notes.contains { $0.source?.externalID == "ANN-2#note" })      // untouched imported note removed
        #expect(s.highlightsKeptLocalEdits == 1 && s.highlightsRemoved == 1)

        // Untouched highlight changed in Apple Books → updated.
        let odyssey = try #require(lib.books.first { $0.title == "The Odyssey" })
        anns[2].selectedText = "Sing to me of the man, Muse."
        lib.mergeAppleBooks(books: snap.books, annotations: anns)
        #expect(lib.book(odyssey.id)?.notes.first?.text == "Sing to me of the man, Muse.")
    }

    @Test func statusNeverMovesBackwards() throws {
        let lib = library()
        let snap = try snapshot()
        lib.mergeAppleBooks(books: snap.books, annotations: [])
        let odyssey = try #require(lib.books.first { $0.title == "The Odyssey" })
        var books = snap.books
        let i = books.firstIndex { $0.assetID == "SAMPLE-A2" }!
        books[i].isFinished = false
        books[i].readingProgress = 0.1   // e.g. user started a re-read on the iPad
        lib.mergeAppleBooks(books: books, annotations: [])
        #expect(lib.book(odyssey.id)?.status == .read)
    }
}
