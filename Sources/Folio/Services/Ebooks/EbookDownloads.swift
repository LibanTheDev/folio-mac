import AppKit
import CryptoKit
import Foundation

/// An EPUB stored by Folio for a book.
struct LocalEbook: Codable, Hashable {
    var fileName: String
    var sha256: String
    var provider: EbookProviderID
    var sourceURL: URL
    var bytes: Int64
    var downloadedAt: Date
}

enum EpubValidator {
    enum Failure: LocalizedError, Equatable {
        case tooSmall, notZip, notEpub
        var errorDescription: String? {
            switch self {
            case .tooSmall: "The download was empty or incomplete."
            case .notZip, .notEpub: "The downloaded file isn't a valid EPUB."
            }
        }
    }

    /// An EPUB is a ZIP container whose first entry is an uncompressed `mimetype` file reading
    /// `application/epub+zip`, with a `META-INF/container.xml`.
    static func validate(_ url: URL) throws {
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        guard data.count >= 1_024 else { throw Failure.tooSmall }
        guard data.prefix(4) == Data([0x50, 0x4B, 0x03, 0x04]) else { throw Failure.notZip }
        let head = data.prefix(120)
        let hasMimetype = head.range(of: Data("mimetype".utf8)) != nil && head.range(of: Data("application/epub+zip".utf8)) != nil
        let hasContainer = data.range(of: Data("META-INF/container.xml".utf8)) != nil
        guard hasMimetype || hasContainer else { throw Failure.notEpub }
    }
}

enum RetryPolicy {
    static let maxAttempts = 3

    /// Retry transient network failures and server errors; never retry client errors or cancellation.
    static func shouldRetry(error: Error?, status: Int?, attempt: Int) -> Bool {
        guard attempt < maxAttempts else { return false }
        if let status { return status == 429 || (500...599).contains(status) }
        guard let e = error as? URLError else { return false }
        return [.timedOut, .networkConnectionLost, .notConnectedToInternet, .cannotConnectToHost,
                .cannotFindHost, .dnsLookupFailed, .resourceUnavailable].contains(e.code)
    }

    static func delay(forAttempt attempt: Int) -> TimeInterval { pow(2, Double(attempt - 1)) }   // 1s, 2s, 4s
}

@MainActor
final class EbookDownloads: ObservableObject {
    enum State: Equatable {
        case downloading(Double?)
        case retrying(attempt: Int)
        case validating
        case done(URL)
        case failed(String)
        case cancelled

        var isActive: Bool {
            switch self {
            case .downloading, .retrying, .validating: true
            default: false
            }
        }
    }

    struct IndexEntry: Codable, Hashable { var fileName: String; var sha256: String; var sourceURL: URL; var bytes: Int64 }

    static let shared = EbookDownloads()

    @Published private(set) var states: [String: State] = [:]
    private var tasks: [String: URLSessionDownloadTask] = [:]
    private var cancelled = Set<String>()
    private(set) var folder: URL
    private var index: [IndexEntry] = []
    /// Called on completion so the library can link the file to a book.
    var onComplete: ((EbookEdition, LocalEbook) -> Void)?

    init(folder: URL? = nil) {
        let base = folder ?? ProcessInfo.processInfo.environment["FOLIO_DATA_DIR"].map { URL(fileURLWithPath: $0) }
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Folio")
        self.folder = folder ?? base.appendingPathComponent("Ebooks", isDirectory: true)
        try? FileManager.default.createDirectory(at: self.folder, withIntermediateDirectories: true)
        loadIndex()
    }

    private var indexURL: URL { folder.appendingPathComponent(".index.json") }

    private func loadIndex() {
        guard let data = try? Data(contentsOf: indexURL), let i = try? JSONDecoder().decode([IndexEntry].self, from: data) else { return }
        index = i.filter { FileManager.default.fileExists(atPath: folder.appendingPathComponent($0.fileName).path) }
    }

    private func saveIndex() {
        if let data = try? JSONEncoder().encode(index) { try? data.write(to: indexURL, options: .atomic) }
    }

    func fileURL(_ entry: IndexEntry) -> URL { folder.appendingPathComponent(entry.fileName) }

    /// A previously downloaded copy of this edition, if one is still on disk.
    func existing(_ edition: EbookEdition) -> URL? {
        index.first { $0.sourceURL == edition.downloadURL }.map(fileURL)
    }

    /// Metadata for a stored download of this edition, for linking it to a book.
    func localEbook(for edition: EbookEdition) -> LocalEbook? {
        index.first { $0.sourceURL == edition.downloadURL }.map {
            LocalEbook(fileName: $0.fileName, sha256: $0.sha256, provider: edition.provider, sourceURL: edition.downloadURL,
                       bytes: $0.bytes, downloadedAt: Date())
        }
    }

    func url(for ebook: LocalEbook) -> URL? {
        let u = folder.appendingPathComponent(ebook.fileName)
        return FileManager.default.fileExists(atPath: u.path) ? u : nil
    }

    func state(for edition: EbookEdition) -> State? {
        if let s = states[edition.id] { return s }
        return existing(edition).map { .done($0) }
    }

    // MARK: Download

    func download(_ edition: EbookEdition) {
        if let url = existing(edition) { states[edition.id] = .done(url); return }   // duplicate: reuse
        guard !(states[edition.id]?.isActive ?? false) else { return }
        cancelled.remove(edition.id)
        Task { await run(edition, attempt: 1) }
    }

    func cancel(_ edition: EbookEdition) {
        cancelled.insert(edition.id)
        tasks[edition.id]?.cancel()
        tasks[edition.id] = nil
        states[edition.id] = .cancelled
    }

    private func run(_ edition: EbookEdition, attempt: Int) async {
        states[edition.id] = .downloading(nil)
        let id = edition.id
        let result = await transfer(edition.downloadURL) { [weak self] progress in
            Task { @MainActor in
                guard let self, !self.cancelled.contains(id) else { return }
                self.states[id] = .downloading(progress)
            }
        } register: { [weak self] task in
            Task { @MainActor in self?.tasks[id] = task }
        }
        tasks[id] = nil
        if cancelled.contains(id) { states[id] = .cancelled; return }

        switch result {
        case .failure(let error):
            let status = (error as? HTTPStatusError)?.status
            if RetryPolicy.shouldRetry(error: error, status: status, attempt: attempt) {
                states[id] = .retrying(attempt: attempt + 1)
                try? await Task.sleep(for: .seconds(RetryPolicy.delay(forAttempt: attempt)))
                if cancelled.contains(id) { states[id] = .cancelled; return }
                await run(edition, attempt: attempt + 1)
            } else {
                states[id] = .failed(status.map { "The server returned an error (\($0))." } ?? error.localizedDescription)
            }
        case .success(let temp):
            states[id] = .validating
            do {
                try EpubValidator.validate(temp)
                let stored = try store(temp, edition: edition)
                states[id] = .done(fileURL(stored))
                onComplete?(edition, LocalEbook(fileName: stored.fileName, sha256: stored.sha256, provider: edition.provider,
                                                sourceURL: edition.downloadURL, bytes: stored.bytes, downloadedAt: Date()))
            } catch {
                try? FileManager.default.removeItem(at: temp)
                states[id] = .failed(error.localizedDescription)
            }
        }
    }

    struct HTTPStatusError: Error { let status: Int }

    private final class Delegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
        let onProgress: (Double?) -> Void
        let onFinish: (Result<URL, Error>) -> Void
        private let lock = NSLock()
        private var done = false

        /// Delivers the result exactly once.
        private func finish(_ r: Result<URL, Error>) {
            lock.lock()
            let first = !done
            done = true
            lock.unlock()
            if first { onFinish(r) }
        }
        init(onProgress: @escaping (Double?) -> Void, onFinish: @escaping (Result<URL, Error>) -> Void) {
            self.onProgress = onProgress; self.onFinish = onFinish
        }

        func urlSession(_ s: URLSession, downloadTask: URLSessionDownloadTask, didWriteData _: Int64, totalBytesWritten w: Int64, totalBytesExpectedToWrite t: Int64) {
            onProgress(t > 0 ? Double(w) / Double(t) : nil)
        }

        func urlSession(_ s: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
            let status = (downloadTask.response as? HTTPURLResponse)?.statusCode ?? 200
            guard status == 200 else { finish(.failure(HTTPStatusError(status: status))); return }
            // The temporary file is deleted when this method returns, so move it now.
            let keep = FileManager.default.temporaryDirectory.appendingPathComponent("folio-\(UUID().uuidString).epub")
            do {
                try FileManager.default.moveItem(at: location, to: keep)
                finish(.success(keep))
            } catch {
                finish(.failure(error))
            }
        }

        func urlSession(_ s: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
            finish(.failure(error ?? URLError(.unknown)))
            s.finishTasksAndInvalidate()
        }
    }

    private nonisolated func transfer(_ url: URL, progress: @escaping (Double?) -> Void,
                                      register: @escaping (URLSessionDownloadTask) -> Void) async -> Result<URL, Error> {
        await withCheckedContinuation { cont in
            let delegate = Delegate(onProgress: progress) { cont.resume(returning: $0) }
            let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
            var req = URLRequest(url: url)
            req.setValue("Folio/1.0 (macOS reading app; user-initiated download)", forHTTPHeaderField: "User-Agent")
            req.timeoutInterval = 60
            let task = session.downloadTask(with: req)
            register(task)
            task.resume()
        }
    }

    /// Moves a validated download into the Ebooks folder, deduplicating by content hash.
    private func store(_ temp: URL, edition: EbookEdition) throws -> IndexEntry {
        let data = try Data(contentsOf: temp, options: .mappedIfSafe)
        let hash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        if let same = index.first(where: { $0.sha256 == hash }) {
            try? FileManager.default.removeItem(at: temp)
            var entry = same
            entry.sourceURL = edition.downloadURL
            if !index.contains(entry) { index.append(entry); saveIndex() }
            return same
        }
        let base = Self.fileBase(edition)
        var name = base + ".epub"
        var n = 2
        while FileManager.default.fileExists(atPath: folder.appendingPathComponent(name).path) {
            name = "\(base) \(n).epub"; n += 1
        }
        try FileManager.default.moveItem(at: temp, to: folder.appendingPathComponent(name))
        let entry = IndexEntry(fileName: name, sha256: hash, sourceURL: edition.downloadURL, bytes: Int64(data.count))
        index.append(entry)
        saveIndex()
        return entry
    }

    static func fileBase(_ e: EbookEdition) -> String {
        let raw = "\(e.authors.first ?? "Unknown") - \(e.title) (\(e.provider.displayName))"
        return String(raw.components(separatedBy: CharacterSet(charactersIn: "/\\:*?\"<>|\n\r")).joined(separator: "-").prefix(150))
    }

    // MARK: Actions

    /// Hands the EPUB to Apple Books, which adds it to the user's Books library (and iCloud, if enabled).
    static func openInAppleBooks(_ url: URL) {
        let books = URL(fileURLWithPath: "/System/Applications/Books.app")
        NSWorkspace.shared.open([url], withApplicationAt: books, configuration: NSWorkspace.OpenConfiguration())
    }
}
