import AppKit
import Foundation

/// Background, read-only synchronization from Apple Books into Folio.
@MainActor
final class AppleBooksSync: ObservableObject {
    enum Status: Equatable {
        case off
        case idle
        case syncing
        case connected
        case notFound(String)
        case permissionNeeded
        case schemaUnsupported(String)
        case error(String)

        var title: String {
            switch self {
            case .off: "Off"
            case .idle: "Waiting to sync"
            case .syncing: "Syncing…"
            case .connected: "Connected"
            case .notFound: "Apple Books data not found"
            case .permissionNeeded: "Permission needed"
            case .schemaUnsupported: "Unsupported Apple Books version"
            case .error: "Sync problem"
            }
        }

        var detail: String? {
            switch self {
            case .notFound(let m), .schemaUnsupported(let m), .error(let m): m
            case .permissionNeeded: "macOS is blocking access to Apple Books data. Open System Settings › Privacy & Security › Full Disk Access and enable Folio, then press Sync Now."
            default: nil
            }
        }

        var isHealthy: Bool { self == .connected || self == .syncing || self == .idle }
    }

    @Published private(set) var status: Status = .off
    @Published private(set) var lastSync: Date?
    @Published private(set) var lastSummary: AppleBooksSyncSummary?
    @Published var enabled: Bool {
        didSet {
            UserDefaults.standard.set(enabled, forKey: "appleBooks.enabled")
            enabled ? start() : stop()
        }
    }

    weak var library: Library?
    private let reader: AppleBooksReader
    private var watchers: [DispatchSourceFileSystemObject] = []
    private var timer: Timer?
    private var debounce: DispatchWorkItem?
    private var activationObserver: NSObjectProtocol?
    private var lastFingerprint: String?
    static let interval: TimeInterval = 300

    init(reader: AppleBooksReader? = nil) {
        let cache = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Folio/AppleBooksSnapshots", isDirectory: true)
        self.reader = reader ?? AppleBooksReader(documentsURL: AppleBooksReader.defaultDocumentsURL(), snapshotRoot: cache)
        self.enabled = UserDefaults.standard.object(forKey: "appleBooks.enabled") as? Bool ?? true
        lastSync = UserDefaults.standard.object(forKey: "appleBooks.lastSync") as? Date
        if let data = UserDefaults.standard.data(forKey: "appleBooks.lastSummary") {
            lastSummary = try? JSONDecoder().decode(AppleBooksSyncSummary.self, from: data)
        }
    }

    func attach(_ library: Library) {
        self.library = library
        if enabled { start() }
    }

    // MARK: Lifecycle

    func start() {
        stop()
        guard enabled else { status = .off; return }
        status = .idle
        installWatchers()
        timer = Timer.scheduledTimer(withTimeInterval: Self.interval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.sync(force: false) }
        }
        activationObserver = NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.sync(force: false) }
        }
        sync(force: true)
    }

    func stop() {
        watchers.forEach { $0.cancel() }
        watchers = []
        timer?.invalidate()
        timer = nil
        if let o = activationObserver { NotificationCenter.default.removeObserver(o) }
        activationObserver = nil
        if !enabled { status = .off }
    }

    /// Watches the database folders (file creation/rename) and the WAL files (writes) so changes made by
    /// Apple Books, including ones arriving from iCloud, trigger a sync within seconds.
    private func installWatchers() {
        var paths = [reader.libraryFolder.path, reader.annotationFolder.path]
        for (folder, prefix) in [(reader.libraryFolder, "BKLibrary"), (reader.annotationFolder, "AEAnnotation")] {
            if let db = try? reader.database(in: folder, prefix: prefix) { paths.append(db.path + "-wal") }
        }
        for path in paths {
            let fd = open(path, O_EVTONLY)
            guard fd >= 0 else { continue }
            let src = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .extend, .rename, .delete], queue: .main)
            src.setEventHandler { [weak self] in
                Task { @MainActor in
                    self?.scheduleDebouncedSync()
                    if src.data.contains(.delete) || src.data.contains(.rename) { self?.installWatchersSoon() }
                }
            }
            src.setCancelHandler { close(fd) }
            src.resume()
            watchers.append(src)
        }
    }

    private func installWatchersSoon() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            guard let self, self.enabled else { return }
            self.watchers.forEach { $0.cancel() }
            self.watchers = []
            self.installWatchers()
        }
    }

    private func scheduleDebouncedSync() {
        debounce?.cancel()
        let work = DispatchWorkItem { [weak self] in Task { @MainActor in self?.sync(force: false) } }
        debounce = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: work)
    }

    // MARK: Sync

    /// Reads a fresh snapshot and merges it. Skips work when Apple's files haven't changed.
    func sync(force: Bool) {
        guard enabled, let library, status != .syncing else { return }
        guard library.loadError == nil else { status = .error("Folio's own library couldn't be read, so syncing is paused."); return }
        let fingerprint = reader.fingerprint()
        if !force, fingerprint == lastFingerprint, status == .connected { return }
        status = .syncing
        let reader = self.reader
        Task.detached(priority: .utility) {
            let result = Result { try reader.read() }
            await MainActor.run {
                switch result {
                case .success(let snapshot):
                    let summary = library.mergeAppleBooks(books: snapshot.books, annotations: snapshot.annotations,
                                                          annotationsAvailable: snapshot.annotationsAvailable)
                    self.lastFingerprint = fingerprint
                    self.lastSync = Date()
                    self.lastSummary = summary
                    UserDefaults.standard.set(self.lastSync, forKey: "appleBooks.lastSync")
                    if let data = try? JSONEncoder().encode(summary) { UserDefaults.standard.set(data, forKey: "appleBooks.lastSummary") }
                    self.status = .connected
                    if summary.booksAdded > 0 { Task { await library.enrichAll() } }
                    if self.watchers.isEmpty { self.installWatchers() }
                case .failure(let error):
                    switch error as? AppleBooksError {
                    case .notInstalled?: self.status = .notFound("Open Apple Books on this Mac once, and make sure iCloud syncing for Books is on.")
                    case .databaseMissing(let which)?: self.status = .notFound("The \(which) database is missing. If you just signed in, iCloud may still be syncing.")
                    case .permissionDenied?: self.status = .permissionNeeded
                    case .schemaUnsupported(let missing)?: self.status = .schemaUnsupported("Missing: \(missing.joined(separator: ", ")). Folio's library was not changed.")
                    default: self.status = .error(error.localizedDescription)
                    }
                }
            }
        }
    }

    // MARK: Derived counts

    var linkedBookCount: Int { library?.books.filter { $0.appleBooksID != nil }.count ?? 0 }
    var importedHighlightCount: Int { library?.books.reduce(0) { $0 + $1.notes.filter { $0.source?.kind == .appleBooks }.count } ?? 0 }
    var confirmedProgressCount: Int { library?.books.filter { $0.externalProgress != nil }.count ?? 0 }
}
