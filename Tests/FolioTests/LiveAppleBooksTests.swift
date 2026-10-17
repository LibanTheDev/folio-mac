import Foundation
import Testing
@testable import Folio

/// Reads the real Apple Books data on this Mac (read-only) and merges into a throwaway Folio library.
/// Opt-in: FOLIO_APPLE_BOOKS_LIVE=1 swift test --filter LiveAppleBooksTests. Prints counts only.
@Suite(.enabled(if: ProcessInfo.processInfo.environment["FOLIO_APPLE_BOOKS_LIVE"] == "1"))
@MainActor struct LiveAppleBooksTests {
    @Test func realDataReadsAndMergesWithoutModifyingAppleBooks() throws {
        let docs = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Containers/com.apple.iBooksX/Data/Documents", isDirectory: true)
        let watched = [docs.appendingPathComponent("BKLibrary"), docs.appendingPathComponent("AEAnnotation")]
        let before = watched.map(fileState)
        let reader = AppleBooksReader(documentsURL: docs, snapshotRoot: tempDir("ab-live-snap"))
        let snap = try reader.read()
        let after = watched.map(fileState)
        #expect(before == after, "Apple Books files changed during the read")

        let lib = Library(directory: tempDir("ab-live-lib"), autosave: false)
        let s = lib.mergeAppleBooks(books: snap.books, annotations: snap.annotations, annotationsAvailable: snap.annotationsAvailable)
        let again = lib.mergeAppleBooks(books: snap.books, annotations: snap.annotations, annotationsAvailable: snap.annotationsAvailable)
        print("LIVE apple books rows:", snap.books.count, "annotation rows:", snap.annotations.count)
        print("LIVE summary:", s)
        print("LIVE provenance:", Dictionary(grouping: lib.books, by: { "\($0.progressProvenance)" }).mapValues(\.count))
        print("LIVE statuses:", Dictionary(grouping: lib.books, by: { $0.status.rawValue }).mapValues(\.count))
        print("LIVE finished with date:", lib.books.filter { $0.status == .read && $0.dateFinished != nil }.count,
              "finished without date:", lib.books.filter { $0.status == .read && $0.dateFinished == nil }.count)
        print("LIVE highlights with chapter:", lib.allNotes.filter { $0.note.chapter != nil }.count, "of", lib.allNotes.count)
        #expect(s.booksSeen > 0)
        #expect(again.booksAdded == 0 && again.highlightsAdded == 0)   // idempotent on real data
    }
}
