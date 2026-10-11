import Charts
import SwiftUI

struct StatsView: View {
    @EnvironmentObject var library: Library
    @State private var year: Int = Calendar.current.component(.year, from: Date())

    private var years: [Int] {
        let cal = Calendar.current
        let ys = Set(library.books.compactMap { $0.dateFinished.map { cal.component(.year, from: $0) } } + [library.currentYear])
        return ys.sorted(by: >)
    }

    var body: some View {
        let finished = library.finished(in: year)
        let pages = finished.compactMap(\.pageCount).reduce(0, +)
        let rated = finished.compactMap(\.rating)
        let avg = rated.isEmpty ? nil : rated.reduce(0, +) / Double(rated.count)

        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                PageHeader(title: "Reading Challenge", caption: String(year)) {
                    Menu {
                        Picker("Year", selection: $year) {
                            ForEach(years, id: \.self) { Text(String($0)).tag($0) }
                        }
                        .pickerStyle(.inline)
                    } label: {
                        Label(String(year), systemImage: "calendar").font(.system(size: 12))
                    }
                    .menuStyle(.button)
                    .buttonStyle(GhostButtonStyle())
                    .menuIndicator(.hidden)
                    .fixedSize()
                }
                HStack(spacing: 14) {
                    StatTile(value: "\(finished.count)", label: "Books read", symbol: "books.vertical")
                    StatTile(value: pages.formatted(), label: "Pages", symbol: "doc.plaintext")
                    StatTile(value: avg.map { $0.formatted(.number.precision(.fractionLength(2))) } ?? "—", label: "Avg. rating", symbol: "star")
                    StatTile(value: finished.isEmpty ? "—" : "\(pages / max(1, finished.count))", label: "Avg. length", symbol: "ruler")
                }

                GoalCard(year: year)

                Card {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Books per Month").font(.system(size: 13, weight: .semibold))
                        Chart(monthly(finished), id: \.month) { item in
                            BarMark(x: .value("Month", item.month, unit: .month), y: .value("Books", item.count), width: .ratio(0.45))
                                .foregroundStyle(Theme.accent)
                                .cornerRadius(4)
                        }
                        .chartXAxis {
                            AxisMarks(values: .stride(by: .month)) { _ in
                                AxisValueLabel(format: .dateTime.month(.narrow), centered: true)
                            }
                        }
                        .chartYAxis { AxisMarks(values: .automatic(desiredCount: 4)) }
                        .frame(height: 180)
                    }
                }

                HStack(alignment: .top, spacing: 16) {
                    Card {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Ratings").font(.system(size: 13, weight: .semibold))
                            Chart(ratingBuckets(rated), id: \.rating) { item in
                                BarMark(x: .value("Count", item.count), y: .value("Rating", item.label))
                                    .foregroundStyle(Theme.accent.opacity(0.75))
                                    .cornerRadius(3)
                            }
                            .chartXAxis(.hidden)
                            .frame(height: 200)
                        }
                    }
                    Card {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Highlights").font(.system(size: 13, weight: .semibold))
                            if let longest = finished.max(by: { $0.pagesValue < $1.pagesValue }), longest.pageCount != nil {
                                highlight("Longest", longest, detail: "\(longest.pagesValue) pages")
                            }
                            if let shortest = finished.filter({ $0.pageCount != nil }).min(by: { $0.pagesValue < $1.pagesValue }) {
                                highlight("Shortest", shortest, detail: "\(shortest.pagesValue) pages")
                            }
                            if let top = finished.filter({ $0.rating != nil }).max(by: { $0.ratingValue < $1.ratingValue }) {
                                highlight("Highest rated", top, detail: "\(top.ratingValue.formatted()) ★")
                            }
                            if finished.isEmpty {
                                Text("Finish a book in \(String(year)) to see highlights.").foregroundStyle(Theme.muted)
                            }
                        }
                    }
                }

                Card {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Most-read Authors · all time").font(.system(size: 13, weight: .semibold))
                        let authors = topAuthors()
                        if authors.isEmpty {
                            Text("Nothing yet.").foregroundStyle(Theme.muted)
                        }
                        ForEach(authors, id: \.name) { a in
                            HStack {
                                Text(a.name)
                                Spacer()
                                Text("\(a.count) book\(a.count == 1 ? "" : "s")").foregroundStyle(Theme.muted).monospacedDigit()
                            }
                            Rectangle().fill(Theme.border).frame(height: 1)
                        }
                    }
                }
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 22)
        }
    }

    private func highlight(_ label: String, _ book: Book, detail: String) -> some View {
        HStack(spacing: 10) {
            CoverView(book: book, size: "S").frame(width: 28)
            VStack(alignment: .leading) {
                Text(label).font(.caption).foregroundStyle(Theme.muted)
                Text(book.title).lineLimit(1)
            }
            Spacer()
            Text(detail).font(.callout).foregroundStyle(Theme.muted)
        }
    }

    private func monthly(_ books: [Book]) -> [(month: Date, count: Int)] {
        let cal = Calendar.current
        return (1...12).map { m in
            let date = cal.date(from: DateComponents(year: year, month: m, day: 1))!
            let count = books.filter { $0.dateFinished.map { cal.component(.month, from: $0) == m } == true }.count
            return (date, count)
        }
    }

    private func ratingBuckets(_ ratings: [Double]) -> [(rating: Double, label: String, count: Int)] {
        stride(from: 5.0, through: 0.5, by: -0.5).map { r in
            (r, r.formatted(.number.precision(.fractionLength(1))) + " ★", ratings.filter { abs($0 - r) < 0.01 }.count)
        }
    }

    private func topAuthors() -> [(name: String, count: Int)] {
        let counts = Dictionary(grouping: library.books(in: .read).compactMap(\.authors.first), by: { $0 }).mapValues(\.count)
        return counts.sorted { $0.value > $1.value || ($0.value == $1.value && $0.key < $1.key) }
            .prefix(6)
            .map { ($0.key, $0.value) }
    }
}

private struct StatTile: View {
    let value: String
    let label: String
    let symbol: String

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 6) {
                Image(systemName: symbol).font(.system(size: 12)).foregroundStyle(Theme.muted)
                Text(value).font(Theme.serif(28, .medium)).monospacedDigit()
                Text(label.uppercased()).font(.system(size: 9.5, weight: .semibold)).tracking(0.6).foregroundStyle(Theme.muted)
            }
        }
    }
}
