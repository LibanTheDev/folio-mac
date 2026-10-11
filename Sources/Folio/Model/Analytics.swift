import Foundation

/// Day-level reading activity derived only from data the user actually recorded:
/// page updates (`progressLog`) and reading sessions. Imports never create activity.
enum Activity {
    struct Day: Hashable {
        var pages = 0
        var seconds: TimeInterval = 0
        var touched = false
    }

    static func daily(books: [Book], sessions: [ReadingSession], calendar cal: Calendar = .current) -> [Date: Day] {
        var days: [Date: Day] = [:]
        for b in books {
            let log = b.progressLog.sorted { $0.date < $1.date }
            for (i, entry) in log.enumerated() {
                let day = cal.startOfDay(for: entry.date)
                let previous: Int?
                if i > 0 {
                    previous = log[i - 1].page
                } else if let started = b.dateStarted, entry.date.timeIntervalSince(started) < 7 * 86_400 {
                    // First update shortly after starting: count from page 0.
                    previous = 0
                } else {
                    previous = nil  // unknown starting point; don't guess
                }
                days[day, default: Day()].touched = true
                if let previous { days[day, default: Day()].pages += max(0, entry.page - previous) }
            }
        }
        for s in sessions {
            let day = cal.startOfDay(for: s.start)
            days[day, default: Day()].touched = true
            days[day, default: Day()].pages += s.pagesRead
            days[day, default: Day()].seconds += s.duration
        }
        return days
    }

    /// Consecutive days with activity ending today (or yesterday, so a streak survives until bedtime).
    static func currentStreak(_ days: [Date: Day], now: Date = Date(), calendar cal: Calendar = .current) -> Int {
        var day = cal.startOfDay(for: now)
        if days[day]?.touched != true { day = cal.date(byAdding: .day, value: -1, to: day)! }
        var streak = 0
        while days[day]?.touched == true {
            streak += 1
            day = cal.date(byAdding: .day, value: -1, to: day)!
        }
        return streak
    }

    static func longestStreak(_ days: [Date: Day], calendar cal: Calendar = .current) -> Int {
        let sorted = days.filter { $0.value.touched }.keys.sorted()
        var best = 0, run = 0
        var prev: Date?
        for d in sorted {
            if let p = prev, cal.date(byAdding: .day, value: 1, to: p) == d { run += 1 } else { run = 1 }
            best = max(best, run)
            prev = d
        }
        return best
    }
}

/// Estimates when the current book will be finished, from the reader's own recent pace for that book.
struct ReadingForecast: Equatable {
    enum Confidence: Equatable { case insufficient, low, good }

    var pagesRemaining: Int?
    var pagesPerDay: Double?
    var finish: Date?
    var earliest: Date?
    var latest: Date?
    var confidence: Confidence

    static func make(book: Book, sessions: [ReadingSession], now: Date = Date(), window: Int = 21,
                     calendar cal: Calendar = .current) -> ReadingForecast {
        guard let pages = book.pageCount, pages > 0 else {
            return ReadingForecast(pagesRemaining: nil, confidence: .insufficient)
        }
        let remaining = max(0, pages - book.currentPage)
        let days = Activity.daily(books: [book], sessions: sessions.filter { $0.bookID == book.id }, calendar: cal)
        let today = cal.startOfDay(for: now)
        let cutoff = cal.date(byAdding: .day, value: -window, to: today)!
        let recent = days.filter { $0.key >= cutoff && $0.value.pages > 0 }
        guard let first = recent.keys.min(), remaining > 0 else {
            return ReadingForecast(pagesRemaining: remaining, confidence: remaining == 0 ? .good : .insufficient)
        }
        // Average over the calendar span since the first recent reading day, including rest days.
        let span = max(1, (cal.dateComponents([.day], from: first, to: today).day ?? 0) + 1)
        let daily = (0..<span).map { offset -> Double in
            let d = cal.date(byAdding: .day, value: offset, to: first)!
            return Double(recent[d]?.pages ?? 0)
        }
        let mean = daily.reduce(0, +) / Double(span)
        guard mean > 0 else { return ReadingForecast(pagesRemaining: remaining, confidence: .insufficient) }
        let variance = daily.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Double(span)
        let sd = variance.squareRoot()
        let readingDays = recent.count
        let confidence: Confidence = readingDays >= 3 && span >= 3 ? .good : .low
        // Wider band when data is thin.
        let spread = confidence == .good ? min(sd / 2, mean * 0.6) : mean * 0.5
        let fast = mean + spread
        let slow = max(mean - spread, mean * 0.35)
        func date(_ pace: Double) -> Date { cal.date(byAdding: .day, value: Int((Double(remaining) / pace).rounded(.up)), to: today)! }
        return ReadingForecast(pagesRemaining: remaining, pagesPerDay: mean, finish: date(mean),
                               earliest: date(fast), latest: date(slow), confidence: confidence)
    }

    /// One-line description suitable for progress panels.
    static func summary(for book: Book, sessions: [ReadingSession], now: Date = Date()) -> String {
        guard let pages = book.pageCount else {
            return "Page \(book.currentPage) · add a page count to see a finish estimate"
        }
        let f = make(book: book, sessions: sessions, now: now)
        var line = "Page \(book.currentPage) of \(pages) · \(f.pagesRemaining ?? 0) left"
        switch f.confidence {
        case .insufficient:
            line += " · not enough reading data to estimate a finish date"
        case .low, .good:
            if let finish = f.finish, let a = f.earliest, let b = f.latest {
                let fmt: (Date) -> String = { $0.formatted(.dateTime.month(.abbreviated).day()) }
                line += " · finish ≈ \(fmt(finish))"
                line += f.confidence == .low ? " (rough guess, \(fmt(a))–\(fmt(b)))" : " (\(fmt(a))–\(fmt(b)))"
            }
        }
        return line
    }
}
