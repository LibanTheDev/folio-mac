import SwiftUI

/// GitHub-style grid of reading activity. Each cell is one day; intensity reflects pages (or time) read.
struct ActivityHeatmap: View {
    let days: [Date: Activity.Day]
    var weeks: Int = 20
    var end: Date = Date()
    var cell: CGFloat = 11
    var spacing: CGFloat = 3
    private let cal = Calendar.current

    private var columns: [[Date]] {
        let today = cal.startOfDay(for: end)
        let weekday = cal.component(.weekday, from: today)
        let offsetToWeekStart = (weekday - cal.firstWeekday + 7) % 7
        let thisWeekStart = cal.date(byAdding: .day, value: -offsetToWeekStart, to: today)!
        let first = cal.date(byAdding: .weekOfYear, value: -(weeks - 1), to: thisWeekStart)!
        return (0..<weeks).map { w in
            (0..<7).map { d in cal.date(byAdding: .day, value: w * 7 + d, to: first)! }
        }
    }

    private var maxValue: Double {
        let values = days.values.map { Double($0.pages) + $0.seconds / 120 }
        return max(1, values.max() ?? 1)
    }

    var body: some View {
        let cols = columns
        let today = cal.startOfDay(for: end)
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top, spacing: spacing) {
                VStack(alignment: .trailing, spacing: spacing) {
                    ForEach(0..<7, id: \.self) { i in
                        Text(i % 2 == 1 ? weekdaySymbol(i) : "")
                            .font(.system(size: 8))
                            .foregroundStyle(DS.textTertiary)
                            .frame(width: 14, height: cell, alignment: .trailing)
                    }
                }
                ForEach(cols.indices, id: \.self) { w in
                    VStack(spacing: spacing) {
                        ForEach(cols[w], id: \.self) { date in
                            let day = days[date]
                            RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                                .fill(color(for: day, future: date > today))
                                .overlay(RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                                    .strokeBorder(date == today ? DS.accent.opacity(0.8) : DS.stroke.opacity(0.5), lineWidth: date == today ? 1 : 0.5))
                                .frame(width: cell, height: cell)
                                .help(tooltip(date, day))
                        }
                    }
                }
            }
            HStack(spacing: 4) {
                Spacer()
                Text("Less").font(.system(size: 9)).foregroundStyle(DS.textTertiary)
                ForEach(0..<5, id: \.self) { level in
                    RoundedRectangle(cornerRadius: 2).fill(levelColor(level)).frame(width: 9, height: 9)
                }
                Text("More").font(.system(size: 9)).foregroundStyle(DS.textTertiary)
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Reading activity for the last \(weeks) weeks: \(days.filter { $0.value.touched && $0.key >= cols[0][0] }.count) reading days")
    }

    private func weekdaySymbol(_ row: Int) -> String {
        let idx = (cal.firstWeekday - 1 + row) % 7
        return String(cal.veryShortWeekdaySymbols[idx])
    }

    private func color(for day: Activity.Day?, future: Bool) -> Color {
        if future { return .clear }
        guard let day, day.touched else { return levelColor(0) }
        let v = Double(day.pages) + day.seconds / 120
        let ratio = v / maxValue
        return levelColor(ratio > 0.75 ? 4 : ratio > 0.45 ? 3 : ratio > 0.15 ? 2 : 1)
    }

    private func levelColor(_ level: Int) -> Color {
        switch level {
        case 0: DS.fill
        case 1: DS.accent.opacity(0.28)
        case 2: DS.accent.opacity(0.5)
        case 3: DS.accent.opacity(0.75)
        default: DS.accent
        }
    }

    private func tooltip(_ date: Date, _ day: Activity.Day?) -> String {
        let d = date.formatted(date: .abbreviated, time: .omitted)
        guard let day, day.touched else { return "\(d): no reading recorded" }
        var parts: [String] = []
        if day.pages > 0 { parts.append("\(day.pages) pages") }
        if day.seconds > 0 { parts.append(day.seconds.readingDuration) }
        return "\(d): " + (parts.isEmpty ? "progress updated" : parts.joined(separator: ", "))
    }
}

/// Heatmap that shows as many weeks as fit the available width (up to `maxWeeks`).
struct AdaptiveHeatmap: View {
    let days: [Date: Activity.Day]
    var maxWeeks = 53
    var cell: CGFloat = 13
    var spacing: CGFloat = 3

    var body: some View {
        GeometryReader { geo in
            let weeks = max(8, min(maxWeeks, Int((geo.size.width - 20) / (cell + spacing))))
            ActivityHeatmap(days: days, weeks: weeks, cell: cell, spacing: spacing)
        }
        .frame(height: 7 * (cell + spacing) + 18)
    }
}
