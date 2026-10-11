import Foundation

/// Everything the analytics page shows for one year. Built only from recorded data.
struct Insights {
    struct Slice: Hashable, Identifiable {
        let name: String
        let count: Int
        var id: String { name }
    }

    let year: Int
    let stats: YearStats
    let daysElapsed: Int
    let pagesPerDay: Double
    /// Share of elapsed days in the year with recorded reading.
    let consistency: Double
    let currentStreak: Int
    let longestStreak: Int
    /// Books completed per month (12 entries).
    let monthlyCompleted: [Int]
    /// Pages from recorded activity per month (12 entries).
    let monthlyLoggedPages: [Int]
    /// Reading time from sessions per month, in seconds (12 entries).
    let monthlySeconds: [TimeInterval]
    /// Primary genre of each book finished this year.
    let genres: [Slice]
    /// All subjects across books finished this year.
    let subjects: [Slice]
    let finishedThisYear: [Book]
    let abandonedThisYear: [Book]
    /// Finished / (finished + abandoned), all time; nil when there's nothing to measure.
    let completionRateAllTime: Double?
    let completionRateYear: Double?
    let activity: [Date: Activity.Day]

    static func make(year: Int, books: [Book], sessions: [ReadingSession], now: Date = Date(),
                     calendar cal: Calendar = .current) -> Insights {
        func inYear(_ d: Date?) -> Bool { d.map { cal.component(.year, from: $0) == year } ?? false }
        let stats = YearStats.make(year: year, books: books, sessions: sessions, calendar: cal)
        let activity = Activity.daily(books: books, sessions: sessions, calendar: cal)

        let currentYear = cal.component(.year, from: now)
        let daysElapsed: Int
        if year < currentYear {
            daysElapsed = cal.range(of: .day, in: .year, for: cal.date(from: DateComponents(year: year, month: 6))!)?.count ?? 365
        } else if year == currentYear {
            daysElapsed = cal.ordinality(of: .day, in: .year, for: now) ?? 1
        } else {
            daysElapsed = 0
        }

        var completed = Array(repeating: 0, count: 12)
        var logged = Array(repeating: 0, count: 12)
        var seconds = Array(repeating: 0.0, count: 12)
        let finished = books.filter { $0.status == .read && inYear($0.dateFinished) }
        for b in finished { completed[cal.component(.month, from: b.dateFinished!) - 1] += 1 }
        for (day, a) in activity where inYear(day) { logged[cal.component(.month, from: day) - 1] += a.pages }
        for s in sessions where inYear(s.start) { seconds[cal.component(.month, from: s.start) - 1] += s.duration }

        func slices(_ names: [String], limit: Int) -> [Slice] {
            let counts = Dictionary(grouping: names, by: { $0 }).map { Slice(name: $0.key, count: $0.value.count) }
                .sorted { $0.count > $1.count || ($0.count == $1.count && $0.name < $1.name) }
            guard counts.count > limit else { return counts }
            let other = counts.dropFirst(limit - 1).reduce(0) { $0 + $1.count }
            return Array(counts.prefix(limit - 1)) + [Slice(name: "Other", count: other)]
        }

        let abandoned = books.filter { $0.status == .dnf && (inYear($0.updatedAt) || inYear($0.dateStarted)) }
        let allFinished = books.filter { $0.status == .read }.count
        let allAbandoned = books.filter { $0.status == .dnf }.count
        let readingDays = activity.filter { inYear($0.key) && $0.value.touched }.count

        return Insights(
            year: year,
            stats: stats,
            daysElapsed: daysElapsed,
            pagesPerDay: daysElapsed > 0 ? Double(stats.pagesRead) / Double(daysElapsed) : 0,
            consistency: daysElapsed > 0 ? Double(readingDays) / Double(daysElapsed) : 0,
            currentStreak: Activity.currentStreak(activity, now: now, calendar: cal),
            longestStreak: Activity.longestStreak(activity, calendar: cal),
            monthlyCompleted: completed,
            monthlyLoggedPages: logged,
            monthlySeconds: seconds,
            genres: slices(finished.compactMap { $0.genres.first }, limit: 7),
            subjects: Array(slices(finished.flatMap(\.genres), limit: 50).filter { $0.name != "Other" }.prefix(10)),
            finishedThisYear: finished,
            abandonedThisYear: abandoned,
            completionRateAllTime: allFinished + allAbandoned > 0 ? Double(allFinished) / Double(allFinished + allAbandoned) : nil,
            completionRateYear: finished.count + abandoned.count > 0 ? Double(finished.count) / Double(finished.count + abandoned.count) : nil,
            activity: activity
        )
    }
}
