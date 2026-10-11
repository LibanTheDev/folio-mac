import Charts
import SwiftUI

struct StatsView: View {
    @EnvironmentObject var library: Library
    @EnvironmentObject var app: AppState
    @State private var year: Int = Calendar.current.component(.year, from: Date())
    @State private var loggingSession = false
    @State private var hoveredMonth: Date?
    @State private var hoveredPagesMonth: Date?

    private var years: [Int] {
        let cal = Calendar.current
        var ys = Set(library.books.compactMap { $0.dateFinished.map { cal.component(.year, from: $0) } })
        ys.formUnion(library.sessions.map { cal.component(.year, from: $0.start) })
        ys.insert(library.currentYear)
        return ys.sorted(by: >)
    }

    var body: some View {
        let insights = Insights.make(year: year, books: library.books, sessions: library.sessions)
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                if library.books.isEmpty {
                    EmptyStateView(icon: "chart.bar.xaxis", title: "Nothing to measure yet",
                                   message: "Add or import books and log some reading, and your analytics will build up here.")
                        .frame(height: 300)
                } else {
                    tiles(insights)
                    HStack(alignment: .top, spacing: 14) {
                        GoalCard(year: year)
                        completionCard(insights)
                    }
                    heatmapCard(insights)
                    HStack(alignment: .top, spacing: 14) {
                        monthlyCompletedChart(insights)
                        monthlyPagesChart(insights)
                    }
                    if !insights.genres.isEmpty {
                        HStack(alignment: .top, spacing: 14) {
                            genreChart(insights)
                            subjectsList(insights)
                        }
                    }
                    forecasts
                    HStack(alignment: .top, spacing: 14) {
                        ratingsChart(insights)
                        highlights(insights)
                    }
                    sessionsCard
                    topAuthors
                }
            }
            .padding(.horizontal, DS.Space.page)
            .padding(.top, 10)
            .padding(.bottom, 30)
        }
        .sheet(isPresented: $loggingSession) {
            LogSessionSheet().environmentObject(library)
        }
    }

    private var header: some View {
        PageHeader(title: "Reading Insights", caption: "Analytics · \(String(year))") {
            HStack(spacing: 8) {
                Button { loggingSession = true } label: { Label("Log Session", systemImage: "plus") }
                    .buttonStyle(GlassButtonStyle())
                Menu {
                    Picker("Year", selection: $year) {
                        ForEach(years, id: \.self) { Text(String($0)).tag($0) }
                    }
                    .pickerStyle(.inline)
                } label: {
                    Label(String(year), systemImage: "calendar")
                }
                .menuStyle(.button)
                .buttonStyle(GlassButtonStyle())
                .menuIndicator(.hidden)
                .fixedSize()
            }
        }
    }

    // MARK: Tiles

    private func tiles(_ i: Insights) -> some View {
        let columns = [GridItem(.adaptive(minimum: 148), spacing: 12)]
        return LazyVGrid(columns: columns, spacing: 14) {
            StatCard(value: "\(i.stats.booksCompleted)", label: "Books completed", icon: "checkmark.seal")
            StatCard(value: i.stats.pagesRead.formatted(), label: "Pages read", icon: "doc.plaintext",
                     footnote: "Finished books + logged pages")
            StatCard(value: i.pagesPerDay.formatted(.number.precision(.fractionLength(1))), label: "Pages per day",
                     icon: "speedometer", footnote: "Averaged over \(i.daysElapsed) days")
            if i.stats.sessionCount > 0 {
                StatCard(value: i.stats.secondsRead.readingDuration, label: "Reading time", icon: "clock",
                         footnote: "From \(i.stats.sessionCount) session\(i.stats.sessionCount == 1 ? "" : "s")")
            }
            if i.activity.values.contains(where: { $0.touched }) {
                StatCard(value: "\(Int((i.consistency * 100).rounded()))%", label: "Consistency", icon: "calendar",
                         footnote: "\(i.stats.readingDays) of \(i.daysElapsed) days with reading")
                StatCard(value: "\(i.currentStreak)d", label: "Current streak", icon: "flame",
                         footnote: "Longest ever: \(i.longestStreak) days")
            }
        }
    }

    private func completionCard(_ i: Insights) -> some View {
        GlassCard {
            HStack(spacing: 18) {
                ZStack {
                    ProgressRing(value: i.completionRateYear ?? i.completionRateAllTime ?? 0, lineWidth: 9, tint: DS.statusRead)
                    Text(percent(i.completionRateYear ?? i.completionRateAllTime))
                        .font(.system(size: 18, weight: .semibold, design: .rounded).monospacedDigit())
                }
                .frame(width: 86, height: 86)
                VStack(alignment: .leading, spacing: 6) {
                    Text("Completion Rate").font(DS.Text.headline)
                    Text(i.completionRateYear != nil
                         ? "\(i.finishedThisYear.count) finished, \(i.abandonedThisYear.count) abandoned in \(String(i.year))."
                         : "No finished or abandoned books in \(String(i.year)) yet.")
                        .font(DS.Text.callout).foregroundStyle(DS.textSecondary)
                    if let all = i.completionRateAllTime {
                        Text("All time: \(percent(all))").font(DS.Text.caption).foregroundStyle(DS.textTertiary)
                    }
                    if !i.abandonedThisYear.isEmpty {
                        Button("Show abandoned books") { app.show(.status(.dnf)) }
                            .buttonStyle(GhostButtonStyle())
                            .padding(.leading, -8)
                    }
                }
            }
        }
    }

    private func percent(_ v: Double?) -> String { v.map { "\(Int(($0 * 100).rounded()))%" } ?? "—" }

    // MARK: Heatmap

    private func heatmapCard(_ i: Insights) -> some View {
        let cal = Calendar.current
        let end = year == library.currentYear ? Date() : cal.date(from: DateComponents(year: year, month: 12, day: 31))!
        return GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: "Reading Activity", subtitle: "\(i.stats.readingDays) reading days in \(String(year))")
                if i.activity.values.contains(where: { $0.touched }) {
                    ScrollView(.horizontal) {
                        ActivityHeatmap(days: i.activity, weeks: 53, end: end, cell: 12, spacing: 3)
                    }
                    .scrollIndicators(.never)
                } else {
                    Text("Update your page or log a session to start building your activity history. Imported books aren't counted, because their reading dates aren't known.")
                        .font(DS.Text.callout).foregroundStyle(DS.textSecondary)
                }
            }
        }
    }

    // MARK: Monthly charts

    private struct MonthValue: Identifiable {
        let month: Date
        let value: Double
        var id: Date { month }
    }

    private func months(_ values: [Double]) -> [MonthValue] {
        let cal = Calendar.current
        return values.enumerated().map { MonthValue(month: cal.date(from: DateComponents(year: year, month: $0.offset + 1, day: 1))!, value: $0.element) }
    }

    private func monthlyCompletedChart(_ i: Insights) -> some View {
        let data = months(i.monthlyCompleted.map(Double.init))
        return chartCard("Books Completed per Month", subtitle: "\(i.stats.booksCompleted) total") {
            Chart(data) { m in
                BarMark(x: .value("Month", m.month, unit: .month), y: .value("Books", m.value), width: .ratio(0.55))
                    .foregroundStyle(DS.chartPrimary.opacity(hoveredMonth == nil || isSameMonth(hoveredMonth, m.month) ? 1 : 0.45))
                    .clipShape(UnevenRoundedRectangle(topLeadingRadius: 4, topTrailingRadius: 4))
                if let h = hoveredMonth, isSameMonth(h, m.month) {
                    RuleMark(x: .value("Month", m.month, unit: .month))
                        .foregroundStyle(.clear)
                        .annotation(position: .top, overflowResolution: .init(x: .fit, y: .disabled)) {
                            tooltip(m.month, "\(Int(m.value)) book\(m.value == 1 ? "" : "s")")
                        }
                }
            }
            .chartXSelection(value: $hoveredMonth)
            .monthAxes(integerStep: max(1, ((i.monthlyCompleted.max() ?? 1) + 3) / 4))
        }
    }

    private func monthlyPagesChart(_ i: Insights) -> some View {
        let data = months(i.monthlyLoggedPages.map(Double.init))
        return chartCard("Logged Pages per Month", subtitle: "from progress updates and sessions") {
            if i.monthlyLoggedPages.allSatisfy({ $0 == 0 }) {
                Text("No logged pages in \(String(year)).").font(DS.Text.callout).foregroundStyle(DS.textTertiary)
                    .frame(maxWidth: .infinity, minHeight: 160)
            } else {
                Chart(data) { m in
                    BarMark(x: .value("Month", m.month, unit: .month), y: .value("Pages", m.value), width: .ratio(0.55))
                        .foregroundStyle(DS.chartSeries[2].opacity(hoveredPagesMonth == nil || isSameMonth(hoveredPagesMonth, m.month) ? 1 : 0.45))
                        .clipShape(UnevenRoundedRectangle(topLeadingRadius: 4, topTrailingRadius: 4))
                    if let h = hoveredPagesMonth, isSameMonth(h, m.month) {
                        RuleMark(x: .value("Month", m.month, unit: .month))
                            .foregroundStyle(.clear)
                            .annotation(position: .top, overflowResolution: .init(x: .fit, y: .disabled)) {
                                tooltip(m.month, "\(Int(m.value).formatted()) pages")
                            }
                    }
                }
                .chartXSelection(value: $hoveredPagesMonth)
                .monthAxes()
            }
        }
    }

    private func isSameMonth(_ a: Date?, _ b: Date) -> Bool {
        guard let a else { return false }
        return Calendar.current.isDate(a, equalTo: b, toGranularity: .month)
    }

    private func tooltip(_ month: Date, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(month.formatted(.dateTime.month(.wide))).font(DS.Text.micro).foregroundStyle(DS.textSecondary)
            Text(value).font(DS.Text.callout.weight(.semibold))
        }
        .padding(.horizontal, 8).padding(.vertical, 5)
        .glass(.control, cornerRadius: DS.Radius.small)
    }

    private func chartCard<C: View>(_ title: String, subtitle: String? = nil, @ViewBuilder _ content: () -> C) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: title, subtitle: subtitle)
                content().frame(height: 180)
            }
        }
    }

    // MARK: Genres

    private func genreChart(_ i: Insights) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: "Genres", subtitle: "books finished in \(String(year))")
                HStack(alignment: .center, spacing: 18) {
                    Chart(Array(i.genres.enumerated()), id: \.element.name) { idx, s in
                        SectorMark(angle: .value("Books", s.count), innerRadius: .ratio(0.6), angularInset: 1.5)
                            .cornerRadius(3)
                            .foregroundStyle(color(for: s.name, index: idx))
                    }
                    .frame(width: 150, height: 150)
                    .accessibilityLabel("Genre distribution")
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(Array(i.genres.enumerated()), id: \.element.name) { idx, s in
                            HStack(spacing: 8) {
                                RoundedRectangle(cornerRadius: 2).fill(color(for: s.name, index: idx)).frame(width: 10, height: 10)
                                Text(s.name).font(DS.Text.callout).lineLimit(1)
                                Spacer()
                                Text("\(s.count)").font(DS.Text.callout.monospacedDigit()).foregroundStyle(DS.textSecondary)
                            }
                        }
                    }
                }
            }
        }
    }

    private func color(for name: String, index: Int) -> Color {
        name == "Other" ? DS.chartOther : DS.chartSeries[index % DS.chartSeries.count]
    }

    private func subjectsList(_ i: Insights) -> some View {
        let maxCount = Double(i.subjects.map(\.count).max() ?? 1)
        return GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: "Subjects", subtitle: "most frequent")
                ForEach(i.subjects) { s in
                    HStack(spacing: 8) {
                        Text(s.name).font(DS.Text.callout).lineLimit(1).frame(width: 130, alignment: .leading)
                        GeometryReader { geo in
                            RoundedRectangle(cornerRadius: 4)
                                .fill(DS.chartPrimary)
                                .frame(width: max(6, geo.size.width * Double(s.count) / maxCount))
                        }
                        .frame(height: 10)
                        Text("\(s.count)").font(DS.Text.caption.monospacedDigit()).foregroundStyle(DS.textSecondary)
                            .frame(width: 22, alignment: .trailing)
                    }
                    .help("\(s.name): \(s.count) book\(s.count == 1 ? "" : "s")")
                }
            }
        }
    }

    // MARK: Forecasts

    @ViewBuilder private var forecasts: some View {
        let reading = library.books(in: .reading)
        if !reading.isEmpty {
            GlassCard {
                VStack(alignment: .leading, spacing: 12) {
                    SectionHeader(title: "Finish Predictions", subtitle: "from your pace over the last 3 weeks")
                    ForEach(reading) { b in
                        let f = ReadingForecast.make(book: b, sessions: library.sessions(for: b.id))
                        HStack(spacing: 12) {
                            CoverView(book: b).frame(width: 30)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(b.title).font(DS.Text.callout.weight(.semibold)).lineLimit(1)
                                ProgressBar(value: b.progress, tint: DS.statusReading, height: 4)
                            }
                            .frame(width: 220)
                            Spacer()
                            VStack(alignment: .trailing, spacing: 2) {
                                Text(forecastHeadline(f, b)).font(DS.Text.callout.weight(.medium))
                                Text(forecastDetail(f)).font(DS.Text.caption).foregroundStyle(DS.textSecondary)
                            }
                        }
                    }
                }
            }
        }
    }

    private func forecastHeadline(_ f: ReadingForecast, _ b: Book) -> String {
        if b.pageCount == nil { return "Add a page count" }
        guard f.confidence != .insufficient, let d = f.finish else { return "Not enough data yet" }
        return "≈ \(d.formatted(.dateTime.month(.abbreviated).day()))"
    }

    private func forecastDetail(_ f: ReadingForecast) -> String {
        let fmt: (Date) -> String = { $0.formatted(.dateTime.month(.abbreviated).day()) }
        switch f.confidence {
        case .insufficient: return "Log progress on a few days to get an estimate"
        case .low:
            if let a = f.earliest, let b = f.latest { return "Rough: \(fmt(a))–\(fmt(b)) · few data points" }
            return "Rough estimate"
        case .good:
            let pace = f.pagesPerDay.map { "\($0.formatted(.number.precision(.fractionLength(0)))) pages/day" } ?? ""
            if let a = f.earliest, let b = f.latest { return "\(fmt(a))–\(fmt(b)) · \(pace)" }
            return pace
        }
    }

    // MARK: Ratings & highlights

    private func ratingsChart(_ i: Insights) -> some View {
        let rated = i.finishedThisYear.compactMap(\.rating)
        let buckets = stride(from: 5.0, through: 0.5, by: -0.5).map { r in
            (label: r.formatted(.number.precision(.fractionLength(1))) + " ★", count: rated.filter { abs($0 - r) < 0.01 }.count)
        }
        return GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: "Ratings", subtitle: rated.isEmpty ? nil : "avg \((rated.reduce(0, +) / Double(rated.count)).formatted(.number.precision(.fractionLength(2))))")
                if rated.isEmpty {
                    Text("No rated books finished in \(String(year)).").font(DS.Text.callout).foregroundStyle(DS.textTertiary)
                } else {
                    Chart(buckets, id: \.label) { b in
                        BarMark(x: .value("Books", b.count), y: .value("Rating", b.label), height: .ratio(0.6))
                            .foregroundStyle(DS.chartSeries[3])
                            .clipShape(UnevenRoundedRectangle(bottomTrailingRadius: 4, topTrailingRadius: 4))
                            .annotation(position: .trailing) {
                                if b.count > 0 { Text("\(b.count)").font(DS.Text.micro).foregroundStyle(DS.textSecondary) }
                            }
                    }
                    .chartXAxis(.hidden)
                    .frame(height: 200)
                }
            }
        }
    }

    private func highlights(_ i: Insights) -> some View {
        let f = i.finishedThisYear
        return GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: "Highlights")
                if let longest = f.filter({ $0.pageCount != nil }).max(by: { $0.pagesValue < $1.pagesValue }) {
                    highlightRow("Longest", longest, "\(longest.pagesValue) pages")
                }
                if let shortest = f.filter({ $0.pageCount != nil }).min(by: { $0.pagesValue < $1.pagesValue }) {
                    highlightRow("Shortest", shortest, "\(shortest.pagesValue) pages")
                }
                if let top = f.filter({ $0.rating != nil }).max(by: { $0.ratingValue < $1.ratingValue }) {
                    highlightRow("Highest rated", top, "\(top.ratingValue.formatted()) ★")
                }
                if let mostNotes = f.max(by: { $0.notes.count < $1.notes.count }), !mostNotes.notes.isEmpty {
                    highlightRow("Most notes", mostNotes, "\(mostNotes.notes.count)")
                }
                if f.isEmpty {
                    Text("Finish a book in \(String(year)) to see highlights.").font(DS.Text.callout).foregroundStyle(DS.textTertiary)
                }
            }
        }
    }

    private func highlightRow(_ label: String, _ book: Book, _ detail: String) -> some View {
        HStack(spacing: 10) {
            CoverView(book: book, size: "S").frame(width: 26)
            VStack(alignment: .leading) {
                Text(label).font(DS.Text.caption).foregroundStyle(DS.textSecondary)
                Text(book.title).font(DS.Text.callout).lineLimit(1)
            }
            Spacer()
            Text(detail).font(DS.Text.callout).foregroundStyle(DS.textSecondary)
        }
        .contentShape(Rectangle())
        .onTapGesture { app.openDetail(book.id) }
    }

    // MARK: Sessions & authors

    private var sessionsCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 8) {
                SectionHeader(title: "Recent Sessions", subtitle: library.sessions.isEmpty ? nil : "\(library.sessions.count) total") {
                    Button { loggingSession = true } label: { Label("Log Session", systemImage: "plus") }
                        .buttonStyle(GhostButtonStyle())
                }
                SessionList(limit: 10)
            }
        }
    }

    private var topAuthors: some View {
        let counts = Dictionary(grouping: library.books(in: .read).compactMap(\.authors.first), by: { $0 }).mapValues(\.count)
        let authors = counts.sorted { $0.value > $1.value || ($0.value == $1.value && $0.key < $1.key) }.prefix(6)
        return GlassCard {
            VStack(alignment: .leading, spacing: 8) {
                SectionHeader(title: "Most-read Authors", subtitle: "all time")
                if authors.isEmpty { Text("Nothing yet.").font(DS.Text.callout).foregroundStyle(DS.textTertiary) }
                ForEach(Array(authors), id: \.key) { a in
                    HStack {
                        Text(a.key).font(DS.Text.callout)
                        Spacer()
                        Text("\(a.value) book\(a.value == 1 ? "" : "s")").font(DS.Text.callout.monospacedDigit()).foregroundStyle(DS.textSecondary)
                    }
                    .padding(.vertical, 3)
                    Rectangle().fill(DS.stroke).frame(height: 1)
                }
            }
        }
    }
}

private extension View {
    /// Month x-axis with recessive grid. Pass `integerStep` for count data so ticks are whole numbers.
    func monthAxes(integerStep: Int? = nil) -> some View {
        self
            .chartXAxis {
                AxisMarks(values: .stride(by: .month)) { _ in
                    AxisValueLabel(format: .dateTime.month(.narrow), centered: true)
                        .foregroundStyle(DS.textTertiary)
                }
            }
            .chartYAxis {
                if let integerStep {
                    AxisMarks(values: .stride(by: Double(integerStep))) { _ in
                        AxisGridLine().foregroundStyle(DS.chartGrid)
                        AxisValueLabel(format: IntegerFormatStyle<Int>()).foregroundStyle(DS.textTertiary)
                    }
                } else {
                    AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                        AxisGridLine().foregroundStyle(DS.chartGrid)
                        AxisValueLabel().foregroundStyle(DS.textTertiary)
                    }
                }
            }
    }
}
