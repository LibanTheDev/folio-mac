import Foundation

extension Library {
    // MARK: Live sessions

    func startSession(_ bookID: UUID, at now: Date = Date()) {
        if let active = activeSession, active.bookID != bookID { finishSession(endPage: nil, at: now) }
        guard let b = book(bookID) else { return }
        if b.status != .reading { setStatus(bookID, .reading, at: now) }
        activeSession = ActiveSession(bookID: bookID, startedAt: now, startPage: book(bookID)?.currentPage ?? 0, resumedAt: now)
    }

    func pauseSession(at now: Date = Date()) {
        guard var s = activeSession, let resumed = s.resumedAt else { return }
        s.accumulated += now.timeIntervalSince(resumed)
        s.resumedAt = nil
        activeSession = s
    }

    func resumeSession(at now: Date = Date()) {
        guard var s = activeSession, s.resumedAt == nil else { return }
        s.resumedAt = now
        activeSession = s
    }

    /// Ends the active session, recording it and updating the book's page.
    @discardableResult
    func finishSession(endPage: Int?, at now: Date = Date()) -> ReadingSession? {
        guard let s = activeSession else { return nil }
        activeSession = nil
        let duration = s.elapsed(at: now)
        let clampedEnd = endPage.map { p in max(0, book(s.bookID)?.pageCount.map { min(p, $0) } ?? p) }
        let session = ReadingSession(bookID: s.bookID, start: s.startedAt, duration: duration,
                                     startPage: s.startPage, endPage: clampedEnd ?? s.startPage)
        // Ignore accidental taps (under 10 seconds with no pages).
        guard duration >= 10 || session.pagesRead > 0 else { return nil }
        sessions.append(session)
        if let end = clampedEnd, end != book(s.bookID)?.currentPage {
            modify(s.bookID) { $0.currentPage = end }
            if let b = book(s.bookID), let pages = b.pageCount, end >= pages { setStatus(s.bookID, .read, at: now) }
        }
        return session
    }

    func discardSession() { activeSession = nil }

    // MARK: Manual history

    func addManualSession(bookID: UUID, start: Date, minutes: Double, startPage: Int?, endPage: Int?) {
        sessions.append(ReadingSession(bookID: bookID, start: start, duration: minutes * 60,
                                       startPage: startPage, endPage: endPage, isManual: true))
        if let end = endPage, let b = book(bookID), end > b.currentPage, b.status == .reading {
            modify(bookID) { $0.currentPage = end }
        }
    }

    func deleteSession(_ id: UUID) { sessions.removeAll { $0.id == id } }

    func sessions(for bookID: UUID) -> [ReadingSession] {
        sessions.filter { $0.bookID == bookID }.sorted { $0.start > $1.start }
    }
}
