import Foundation

/// A timed reading session. Only created by the user (live or entered manually), never inferred.
struct ReadingSession: Codable, Hashable, Identifiable {
    var id = UUID()
    var bookID: UUID
    var start: Date
    /// Active reading time in seconds (pauses excluded).
    var duration: TimeInterval
    var startPage: Int?
    var endPage: Int?
    var isManual = false

    var pagesRead: Int { max(0, (endPage ?? 0) - (startPage ?? endPage ?? 0)) }

    init(id: UUID = UUID(), bookID: UUID, start: Date, duration: TimeInterval, startPage: Int?, endPage: Int?, isManual: Bool = false) {
        self.id = id; self.bookID = bookID; self.start = start; self.duration = duration
        self.startPage = startPage; self.endPage = endPage; self.isManual = isManual
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.value(.id, UUID())
        bookID = try c.decode(UUID.self, forKey: .bookID)
        start = c.value(.start, Date())
        duration = c.value(.duration, 0)
        startPage = c.value(.startPage, nil)
        endPage = c.value(.endPage, nil)
        isManual = c.value(.isManual, false)
    }
}

/// The in-progress session, persisted so quitting the app doesn't lose it.
struct ActiveSession: Codable, Hashable {
    var bookID: UUID
    var startedAt: Date
    var startPage: Int
    /// Time accumulated before the current run segment.
    var accumulated: TimeInterval = 0
    /// Start of the current run segment; nil while paused.
    var resumedAt: Date?

    var isPaused: Bool { resumedAt == nil }

    func elapsed(at now: Date = Date()) -> TimeInterval {
        accumulated + (resumedAt.map { now.timeIntervalSince($0) } ?? 0)
    }
}
