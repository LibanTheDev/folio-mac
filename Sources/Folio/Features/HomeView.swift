import SwiftUI

struct HomeView: View {
    @EnvironmentObject var library: Library
    @EnvironmentObject var app: AppState
    @Environment(\.openBook) private var openBook

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 30) {
                greeting
                if library.books.isEmpty {
                    welcome
                } else {
                    HStack(alignment: .top, spacing: 16) {
                        GoalCard(year: library.currentYear)
                        StreakCard()
                    }
                    currentlyReading
                    shelfRow(title: "Up Next", books: Array(library.books(in: .wantToRead).sorted { $0.dateAdded > $1.dateAdded }.prefix(10)), more: .status(.wantToRead))
                    shelfRow(title: "Recently Finished", books: Array(library.books(in: .read).sorted { $0.finishedValue > $1.finishedValue }.prefix(10)), more: .status(.read))
                }
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 22)
        }
    }

    private var greeting: some View {
        let hour = Calendar.current.component(.hour, from: Date())
        let part = hour < 12 ? "Good morning" : hour < 18 ? "Good afternoon" : "Good evening"
        return VStack(alignment: .leading, spacing: 4) {
            Text(Date().formatted(.dateTime.weekday(.wide).month(.wide).day()).uppercased())
                .font(.system(size: 10, weight: .semibold))
                .tracking(0.8)
                .foregroundStyle(DS.textSecondary)
            Text(part).font(DS.serif(32, .medium))
        }
    }

    private var welcome: some View {
        GlassCard(padding: 24) {
            VStack(alignment: .leading, spacing: 14) {
                Text("Welcome to Folio").font(DS.serif(22, .medium))
                Text("A calm, private home for your reading life. Your data stays on this Mac. No ads, no feed, no tracking.")
                    .foregroundStyle(DS.textSecondary)
                HStack(spacing: 10) {
                    Button { library.importGoodreads() } label: {
                        Label("Import from Goodreads", systemImage: "square.and.arrow.down")
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .fixedSize()
                    Button { app.go(.discover) } label: { Label("Discover Books", systemImage: "safari") }
                        .buttonStyle(GlassButtonStyle())
                    Button { library.presentAddBook() } label: { Label("Add Manually", systemImage: "plus") }
                        .buttonStyle(GlassButtonStyle())
                }
                Text("On Goodreads: My Books → Import and export → Export Library, then choose the downloaded CSV.")
                    .font(.caption)
                    .foregroundStyle(DS.textSecondary)
            }
        }
    }

    @ViewBuilder private var currentlyReading: some View {
        let reading = library.books(in: .reading)
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: "Currently Reading", subtitle: reading.isEmpty ? nil : "\(reading.count)")
            if reading.isEmpty {
                Text("Nothing in progress. Pick something from Up Next.").foregroundStyle(DS.textSecondary)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 330), spacing: 14)], spacing: 14) {
                    ForEach(reading) { ReadingCard(book: $0, selected: app.selectedBook == $0.id) }
                }
            }
        }
    }

    @ViewBuilder
    private func shelfRow(title: String, books: [Book], more: Scope) -> some View {
        if !books.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    SectionHeader(title: title)
                    Button("See all") { app.show(more) }
                        .buttonStyle(GlassButtonStyle())
                }
                ScrollView(.horizontal) {
                    HStack(alignment: .top, spacing: 20) {
                        ForEach(books) { book in
                            BookTile(book: book, selected: app.selectedBook == book.id)
                                .frame(width: 118)
                                .onTapGesture { openBook(book.id) }
                        }
                    }
                    .padding(.vertical, 6)
                    .padding(.horizontal, 2)
                }
                .scrollIndicators(.never)
            }
        }
    }
}

private struct ReadingCard: View {
    @EnvironmentObject var library: Library
    @Environment(\.openBook) private var openBook
    let book: Book
    var selected = false
    @State private var showingUpdate = false
    @State private var page = ""

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            CoverView(book: book).frame(width: 66)
            VStack(alignment: .leading, spacing: 4) {
                if let started = book.dateStarted {
                    Text("Started \(started.numericString)").font(.system(size: 10)).foregroundStyle(DS.textSecondary)
                }
                Text(book.title).font(.system(size: 14, weight: .semibold)).lineLimit(2)
                Text(book.authorLine).font(.system(size: 12)).foregroundStyle(DS.textSecondary).lineLimit(1)
                Spacer(minLength: 6)
                ProgressBar(value: book.progress)
                HStack {
                    Text(book.pageCount.map { "p. \(book.currentPage) of \($0) · \(Int(book.progress * 100))%" } ?? "p. \(book.currentPage)")
                        .font(.system(size: 10.5).monospacedDigit())
                        .foregroundStyle(DS.textSecondary)
                    Spacer()
                    Button("Update") { page = String(book.currentPage); showingUpdate = true }
                        .buttonStyle(GlassButtonStyle())
                        .popover(isPresented: $showingUpdate, arrowEdge: .bottom) {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("What page are you on?").font(.headline)
                                HStack {
                                    TextField("Page", text: $page).frame(width: 80).onSubmit(save)
                                    if let p = book.pageCount { Text("of \(p)").foregroundStyle(.secondary) }
                                }
                                HStack {
                                    Button("I finished it!") {
                                        library.setStatus(book.id, .read); showingUpdate = false
                                    }
                                    Spacer()
                                    Button("Save", action: save).keyboardShortcut(.defaultAction)
                                }
                            }
                            .padding(16)
                            .frame(width: 260)
                        }
                }
            }
        }
        .frame(height: 99)
        .padding(14)
        .hoverGlass(selected: selected)
        .contentShape(Rectangle())
        .onTapGesture { openBook(book.id) }
    }

    private func save() {
        if let p = Int(page) { library.logProgress(book.id, page: p) }
        showingUpdate = false
    }
}

struct GoalCard: View {
    @EnvironmentObject var library: Library
    let year: Int

    var body: some View {
        let goal = library.goals[year] ?? 0
        let done = library.finished(in: year).count
        let fraction = goal > 0 ? min(1, Double(done) / Double(goal)) : 0
        GlassCard {
            HStack(spacing: 20) {
                ZStack {
                    Circle().stroke(DS.fill, lineWidth: 9)
                    Circle().trim(from: 0, to: fraction)
                        .stroke(DS.accent, style: StrokeStyle(lineWidth: 9, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .animation(.spring, value: fraction)
                    VStack(spacing: 0) {
                        Text("\(done)").font(DS.serif(26, .semibold).monospacedDigit())
                        if goal > 0 { Text("of \(goal)").font(.system(size: 10)).foregroundStyle(DS.textSecondary) }
                    }
                }
                .frame(width: 88, height: 88)
                VStack(alignment: .leading, spacing: 6) {
                    Text("\(String(year)) Reading Challenge").font(.system(size: 13, weight: .semibold))
                    Text(paceMessage(done: done, goal: goal)).font(.system(size: 12)).foregroundStyle(DS.textSecondary)
                    Stepper(value: Binding(get: { goal }, set: { library.goals[year] = max(0, $0) }), in: 0...500) {
                        Text(goal == 0 ? "Set a goal" : "Goal: \(goal) books").font(.system(size: 12))
                    }
                    .padding(.top, 4)
                }
            }
        }
    }

    private func paceMessage(done: Int, goal: Int) -> String {
        guard goal > 0 else { return "Set a yearly goal to track your pace." }
        if done >= goal { return "Goal reached. Everything from here is a bonus." }
        if year != library.currentYear { return "\(goal - done) short of the goal." }
        let cal = Calendar.current
        let dayOfYear = Double(cal.ordinality(of: .day, in: .year, for: Date()) ?? 1)
        let daysInYear = Double(cal.range(of: .day, in: .year, for: Date())?.count ?? 365)
        let diff = Int((Double(done) - Double(goal) * dayOfYear / daysInYear).rounded())
        if diff > 0 { return "\(diff) book\(diff == 1 ? "" : "s") ahead of schedule." }
        if diff < 0 { return "\(-diff) book\(diff == -1 ? "" : "s") behind schedule. You've got this." }
        return "Right on track."
    }
}

private struct StreakCard: View {
    @EnvironmentObject var library: Library

    var body: some View {
        let cal = Calendar.current
        let days = Set(library.books.flatMap(\.progressLog).map { cal.startOfDay(for: $0.date) })
        var streak = 0
        var day = cal.startOfDay(for: Date())
        if !days.contains(day) { day = cal.date(byAdding: .day, value: -1, to: day)! }
        while days.contains(day) { streak += 1; day = cal.date(byAdding: .day, value: -1, to: day)! }
        let weekStart = cal.date(byAdding: .day, value: -6, to: cal.startOfDay(for: Date()))!
        let last7 = (0..<7).map { cal.date(byAdding: .day, value: $0, to: weekStart)! }

        return GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    Image(systemName: "flame").foregroundStyle(streak > 0 ? DS.accent : DS.textTertiary)
                    Text(streak == 1 ? "1-day streak" : "\(streak)-day streak").font(.system(size: 13, weight: .semibold))
                }
                Text("Log your page any day you read.")
                    .font(.system(size: 12)).foregroundStyle(DS.textSecondary)
                HStack(spacing: 9) {
                    ForEach(last7, id: \.self) { d in
                        VStack(spacing: 5) {
                            Circle()
                                .fill(days.contains(d) ? DS.accent : DS.fill)
                                .frame(width: 18, height: 18)
                            Text(d.formatted(.dateTime.weekday(.narrow))).font(.system(size: 9.5)).foregroundStyle(DS.textSecondary)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: 310)
    }
}
