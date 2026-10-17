import Foundation
import Testing
@testable import Folio

func fixtureData(_ name: String, _ ext: String) throws -> Data {
    try Data(contentsOf: try #require(Bundle.module.url(forResource: name, withExtension: ext, subdirectory: "Fixtures")))
}

/// Builds a real EPUB container with the system zip tool (mimetype stored first, uncompressed).
func makeEpub(in dir: URL, name: String = "book", body: String = "Hello") throws -> URL {
    let root = dir.appendingPathComponent("src-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: root.appendingPathComponent("META-INF"), withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: root.appendingPathComponent("OEBPS"), withIntermediateDirectories: true)
    try "application/epub+zip".write(to: root.appendingPathComponent("mimetype"), atomically: true, encoding: .utf8)
    try #"<?xml version="1.0"?><container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container"><rootfiles><rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/></rootfiles></container>"#
        .write(to: root.appendingPathComponent("META-INF/container.xml"), atomically: true, encoding: .utf8)
    // Varied text so the archive doesn't compress below a realistic size.
    try (0..<200).map { "<p>\(body) \(UUID().uuidString) \($0)</p>" }.joined(separator: "\n")
        .write(to: root.appendingPathComponent("OEBPS/text.xhtml"), atomically: true, encoding: .utf8)
    try "<package/>".write(to: root.appendingPathComponent("OEBPS/content.opf"), atomically: true, encoding: .utf8)
    let out = dir.appendingPathComponent("\(name).epub")
    for args in [["-X0", out.path, "mimetype"], ["-Xr9D", out.path, "META-INF", "OEBPS"]] {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        p.currentDirectoryURL = root
        p.arguments = ["-q"] + args
        try p.run(); p.waitUntilExit()
    }
    return out
}

@Suite struct EbookProviderTests {
    @Test func gutenbergOPDSParsesSearchAndPublicDomainBook() throws {
        let candidates = GutenbergProvider.parseSearch(try fixtureData("gutenberg-search-pride", "xml"))
        #expect(candidates.contains { $0.bookID == "1342" && $0.title == "Pride and Prejudice" && $0.author == "Jane Austen" })
        let e = try #require(GutenbergProvider.parseBook(try fixtureData("gutenberg-book-1342", "xml"), bookID: "1342"))
        #expect(e.provider == .gutenberg && e.title == "Pride and Prejudice" && e.language == "en")
        #expect(e.downloadURL.absoluteString.hasPrefix("https://www.gutenberg.org/ebooks/1342.epub"))
        #expect((e.fileSize ?? 0) > 100_000)
        #expect(e.rights.hasPrefix("Public domain in the USA."))
        #expect(e.listingURL.absoluteString == "https://www.gutenberg.org/ebooks/1342")

        // A book Gutenberg marks as copyrighted is never offered.
        let copyrighted = try String(decoding: fixtureData("gutenberg-book-1342", "xml"), as: UTF8.self)
            .replacingOccurrences(of: "Public domain in the USA.", with: "Copyrighted. Read the copyright notice inside this book for details.")
        #expect(GutenbergProvider.parseBook(Data(copyrighted.utf8), bookID: "1342") == nil)
    }

    @Test func standardEbooksParsesCompatibleEpubWithSizeAndRights() throws {
        let editions = StandardEbooksProvider.parse(try fixtureData("standardebooks-meditations", "xml"))
        let e = try #require(editions.first)
        #expect(e.title == "Meditations")
        #expect(e.authors.contains { $0.contains("Aurelius") })
        #expect(e.downloadURL.pathExtension == "epub" && !e.downloadURL.absoluteString.contains("advanced") && !e.downloadURL.absoluteString.contains("kepub"))
        #expect(e.downloadURL.absoluteString.hasSuffix("?source=feed"))   // required by the site to serve the file
        #expect((e.fileSize ?? 0) > 10_000)
        #expect(e.rights.hasPrefix("Public domain in the United States"))
        #expect(e.listingURL.host == "standardebooks.org")
    }

    @Test func matchingFiltersByTitleAndAuthor() {
        func ed(_ t: String, _ a: String, _ p: EbookProviderID = .gutenberg) -> EbookEdition {
            EbookEdition(provider: p, title: t, authors: [a], formatLabel: "EPUB", downloadURL: URL(string: "https://x/\(UUID())")!,
                         listingURL: URL(string: "https://x")!, rights: "")
        }
        let q = EbookQuery(title: "Meditations: A New Translation", author: "Marcus Aurelius")
        let ranked = EbookMatching.rank([ed("The Meditations of the Emperor Marcus Aurelius Antoninus", "Marcus Aurelius"),
                                         ed("Meditations", "Marcus Aurelius", .standardEbooks),
                                         ed("Meditations on First Philosophy", "René Descartes"),
                                         ed("Something Else", "Marcus Aurelius")], for: q)
        #expect(ranked.map(\.title) == ["Meditations", "The Meditations of the Emperor Marcus Aurelius Antoninus"])
        #expect(GutenbergProvider.displayName("Austen, Jane") == "Jane Austen")
    }
}

@Suite struct DownloadPolicyTests {
    @Test func retriesOnlyTransientFailures() {
        #expect(RetryPolicy.shouldRetry(error: URLError(.timedOut), status: nil, attempt: 1))
        #expect(RetryPolicy.shouldRetry(error: nil, status: 503, attempt: 2))
        #expect(RetryPolicy.shouldRetry(error: nil, status: 429, attempt: 1))
        #expect(!RetryPolicy.shouldRetry(error: nil, status: 404, attempt: 1))
        #expect(!RetryPolicy.shouldRetry(error: URLError(.cancelled), status: nil, attempt: 1))
        #expect(!RetryPolicy.shouldRetry(error: URLError(.timedOut), status: nil, attempt: 3))
        #expect(RetryPolicy.delay(forAttempt: 3) == 4)
    }

    @Test func validatorAcceptsEpubsAndRejectsOtherFiles() throws {
        let dir = tempDir("epub")
        try EpubValidator.validate(try makeEpub(in: dir))
        let html = dir.appendingPathComponent("page.epub")
        try String(repeating: "<html>not an epub</html>", count: 100).write(to: html, atomically: true, encoding: .utf8)
        #expect(throws: EpubValidator.Failure.notZip) { try EpubValidator.validate(html) }
        let tiny = dir.appendingPathComponent("tiny.epub")
        try Data([0x50, 0x4B, 0x03, 0x04]).write(to: tiny)
        #expect(throws: EpubValidator.Failure.tooSmall) { try EpubValidator.validate(tiny) }
        // A plain zip that isn't an EPUB.
        let zipSrc = dir.appendingPathComponent("plain.txt")
        try (0..<200).map { _ in UUID().uuidString }.joined(separator: "\n").write(to: zipSrc, atomically: true, encoding: .utf8)
        let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/bin/zip"); p.currentDirectoryURL = dir
        p.arguments = ["-q", "plain.zip", "plain.txt"]; try p.run(); p.waitUntilExit()
        #expect(throws: EpubValidator.Failure.notEpub) { try EpubValidator.validate(dir.appendingPathComponent("plain.zip")) }
    }
}

@MainActor @Suite(.serialized) struct DownloadManagerTests {
    func edition(_ url: URL, title: String = "Walden") -> EbookEdition {
        EbookEdition(provider: .gutenberg, title: title, authors: ["Henry David Thoreau"], formatLabel: "EPUB",
                     downloadURL: url, listingURL: URL(string: "https://www.gutenberg.org/ebooks/205")!, rights: "Public domain")
    }

    func waitUntilSettled(_ m: EbookDownloads, _ e: EbookEdition) async {
        for _ in 0..<200 {
            if let s = m.states[e.id], !s.isActive { return }
            try? await Task.sleep(for: .milliseconds(25))
        }
    }

    @Test func downloadsValidatesStoresAndDeduplicates() async throws {
        let src = tempDir("dl-src")
        let a = try makeEpub(in: src, name: "a")
        let copy = src.appendingPathComponent("same-content.epub")
        try FileManager.default.copyItem(at: a, to: copy)
        let folder = tempDir("dl-dest")
        let m = EbookDownloads(folder: folder)
        var completions = 0
        m.onComplete = { _, _ in completions += 1 }

        let e1 = edition(a)
        m.download(e1)
        await waitUntilSettled(m, e1)
        guard case .done(let stored)? = m.states[e1.id] else { Issue.record("not done: \(String(describing: m.states[e1.id]))"); return }
        #expect(stored.lastPathComponent == "Henry David Thoreau - Walden (Project Gutenberg).epub")
        try EpubValidator.validate(stored)
        #expect(m.localEbook(for: e1)?.bytes ?? 0 > 0)

        // Same URL again: reused without downloading.
        m.download(e1)
        #expect(m.states[e1.id] == .done(stored))

        // Different URL, identical bytes: deduplicated by hash.
        let e2 = edition(copy, title: "Walden (copy)")
        m.download(e2)
        await waitUntilSettled(m, e2)
        #expect(m.states[e2.id] == .done(stored))
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path).filter { $0.hasSuffix(".epub") }.count == 1)
        #expect(completions == 2)

        // The index survives a restart.
        let reopened = EbookDownloads(folder: folder)
        #expect(reopened.existing(e1) == stored)
    }

    @Test func invalidFilesAreRejectedAndRemoved() async throws {
        let src = tempDir("dl-bad")
        let bad = src.appendingPathComponent("login-page.epub")
        try String(repeating: "<html>Please sign in</html>", count: 100).write(to: bad, atomically: true, encoding: .utf8)
        let folder = tempDir("dl-bad-dest")
        let m = EbookDownloads(folder: folder)
        let e = edition(bad)
        m.download(e)
        await waitUntilSettled(m, e)
        guard case .failed? = m.states[e.id] else { Issue.record("expected failure"); return }
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path).filter { $0.hasSuffix(".epub") }.isEmpty)
    }

    @Test func missingFileFailsWithoutRetryLoop() async throws {
        let m = EbookDownloads(folder: tempDir("dl-missing"))
        let e = edition(URL(fileURLWithPath: "/nonexistent/folio-\(UUID()).epub"))
        m.download(e)
        await waitUntilSettled(m, e)
        guard case .failed? = m.states[e.id] else { Issue.record("expected failure: \(String(describing: m.states[e.id]))"); return }
    }
}

/// Live catalog checks. Run with FOLIO_NETWORK_TESTS=1 swift test --filter LiveEbookTests
@Suite(.enabled(if: ProcessInfo.processInfo.environment["FOLIO_NETWORK_TESTS"] == "1"))
@MainActor struct LiveEbookTests {
    @Test func publicDomainBooksAreFoundAndModernOnesAreNot() async {
        let pride = await EbookSearch.find(EbookQuery(title: "Pride and Prejudice", author: "Jane Austen"))
        print("LIVE pride:", pride.editions.map { "\($0.provider.displayName): \($0.title) \($0.fileSize.map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) } ?? "?")" }, "failed:", pride.failedProviders)
        #expect(pride.editions.contains { $0.provider == .standardEbooks })
        #expect(pride.editions.contains { $0.provider == .gutenberg })
        #expect(pride.editions.allSatisfy { $0.fileSize != nil })
        let modern = await EbookSearch.find(EbookQuery(title: "Project Hail Mary", author: "Andy Weir"))
        print("LIVE modern:", modern.editions.count)
        #expect(modern.editions.isEmpty)
        let byISBN = await EbookSearch.find(EbookQuery(title: "", author: nil, isbn: "9780141439518"))   // Pride and Prejudice (Penguin)
        print("LIVE isbn:", byISBN.editions.map(\.title))
        #expect(!byISBN.editions.isEmpty)
    }

    @Test func realStandardEbooksDownloadValidates() async throws {
        let found = await EbookSearch.find(EbookQuery(title: "Meditations", author: "Marcus Aurelius"))
        let e = try #require(found.editions.first { $0.provider == .standardEbooks })
        let m = EbookDownloads(folder: tempDir("live-dl"))
        m.download(e)
        for _ in 0..<600 {
            if let s = m.states[e.id], !s.isActive { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        guard case .done(let url)? = m.states[e.id] else { Issue.record("download: \(String(describing: m.states[e.id]))"); return }
        print("LIVE downloaded:", url.lastPathComponent, (try? FileManager.default.attributesOfItem(atPath: url.path)[.size]) ?? "")
        try EpubValidator.validate(url)
    }
}
