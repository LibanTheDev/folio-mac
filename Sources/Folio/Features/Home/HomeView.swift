import SwiftUI

struct HomeView: View {
    @EnvironmentObject var library: Library
    @EnvironmentObject var app: AppState

    var body: some View {
        let year = library.currentYear
        let stats = YearStats.make(year: year, books: library.books, sessions: library.sessions)
        let activity = Activity.daily(books: library.books, sessions: library.sessions)
        ScrollView {
            VStack(alignment: .leading, spacing: 30) {
                greeting
                if library.books.isEmpty {
                    WelcomeCard()
                } else {
                    if let s = library.activeSession { SessionBanner(session: s) }
                    statRow(stats, activity: activity)
                    currentlyReading
                    HStack(alignment: .top, spacing: 16) {
                        UpNextQueue().frame(maxWidth: .infinity)
                        GoalCard(year: year).frame(width: 340)
                    }
                    recentKnowledge
                    activitySection(activity)
                    recentlyFinished
                }
            }
            .padding(.horizontal, DS.Space.page)
            .padding(.top, 10)
            .padding(.bottom, 30)
        }
    }

    // MARK: Header

    private var greeting: some View {
        TimelineView(.everyMinute) { ctx in
            let hour = Calendar.current.component(.hour, from: ctx.date)
            let part = hour < 5 ? "Good evening" : hour < 12 ? "Good morning" : hour < 18 ? "Good afternoon" : "Good evening"
            VStack(alignment: .leading, spacing: 5) {
                Text(ctx.date.formatted(.dateTime.weekday(.wide).month(.wide).day()).uppercased())
                    .font(DS.Text.eyebrow).tracking(0.9)
                    .foregroundStyle(DS.textTertiary)
                Text("\(part).").font(DS.serif(34, .semibold))
                Text("A little reading every day adds up.")
                    .font(.system(size: 14))
                    .foregroundStyle(DS.textSecondary)
            }
        }
    }

    // MARK: Stats

    @ViewBuilder
    private func statRow(_ stats: YearStats, activity: [Date: Activity.Day]) -> some View {
        let streak = Activity.currentStreak(activity)
        let hasActivity = activity.values.contains { $0.touched }
        HStack(spacing: 14) {
            StatCard(value: "\(stats.booksCompleted)", label: "Books completed in \(String(stats.year))", icon: "checkmark.seal")
            StatCard(value: stats.pagesRead.formatted(), label: "Pages read this year", icon: "doc.plaintext",
                     footnote: "Finished books + logged progress")
            if hasActivity {
                StatCard(value: "\(streak) day\(streak == 1 ? "" : "s")", label: "Current streak", icon: "flame",
                         footnote: "Longest: \(Activity.longestStreak(activity)) days")
            }
            if stats.sessionCount > 0 {
                StatCard(value: stats.secondsRead.readingDuration, label: "Reading time this year", icon: "clock",
                         footnote: "\(stats.sessionCount) session\(stats.sessionCount == 1 ? "" : "s")")
            }
        }
    }

    // MARK: Currently reading

    @ViewBuilder private var currentlyReading: some View {
        let reading = library.books(in: .reading).sorted { $0.updatedAt > $1.updatedAt }
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: "Currently Reading", subtitle: reading.isEmpty ? nil : "\(reading.count)")
            if reading.isEmpty {
                Text("Nothing in progress. Pick something from Up Next.")
                    .font(DS.Text.body).foregroundStyle(DS.textSecondary)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 360), spacing: 14)], spacing: 14) {
                    ForEach(reading) { ReadingCard(book: $0, selected: app.selectedBook == $0.id) }
                }
            }
        }
    }

    // MARK: Knowledge

    @ViewBuilder private var recentKnowledge: some View {
        let notes = Array(library.allNotes.prefix(6))
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: "Recent Knowledge", subtitle: notes.isEmpty ? nil : "\(library.allNotes.count) saved")
            if notes.isEmpty {
                Text("Highlights, quotes and reflections you save on any book will collect here.")
                    .font(DS.Text.body).foregroundStyle(DS.textSecondary)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 260), spacing: 14, alignment: .top)], spacing: 14) {
                    ForEach(notes) { ref in KnowledgeCard(ref: ref) }
                }
            }
        }
    }

    // MARK: Activity

    @ViewBuilder
    private func activitySection(_ activity: [Date: Activity.Day]) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: "Reading Activity", subtitle: "recent weeks")
            GlassCard {
                if activity.values.contains(where: { $0.touched }) {
                    AdaptiveHeatmap(days: activity, maxWeeks: 30)
                } else {
                    Text("Update your page or run a reading session to start your activity map. Imported history isn't counted as activity.")
                        .font(DS.Text.callout).foregroundStyle(DS.textSecondary)
                }
            }
        }
    }

    // MARK: Recently finished

    @ViewBuilder private var recentlyFinished: some View {
        let books = Array(library.books(in: .read).sorted { $0.finishedValue > $1.finishedValue }.prefix(12))
        if !books.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                SectionHeader(title: "Recently Finished") {
                    Button("See all") { app.show(.status(.read)) }.buttonStyle(GhostButtonStyle())
                }
                ScrollView(.horizontal) {
                    HStack(alignment: .top, spacing: 20) {
                        ForEach(books) { book in
                            BookTile(book: book, selected: app.selectedBook == book.id)
                                .frame(width: 112)
                                .onTapGesture(count: 2) { app.openDetail(book.id) }
                                .onTapGesture { app.open(book.id) }
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

// MARK: - Pieces

struct WelcomeCard: View {
    @EnvironmentObject var library: Library
    @EnvironmentObject var app: AppState

    var body: some View {
        GlassCard(padding: 26) {
            VStack(alignment: .leading, spacing: 14) {
                Text("Welcome to Folio").font(DS.serif(24, .semibold))
                Text("A calm, private home for your reading life, and for what you learn from it. Your data stays on this Mac. No ads, no feed, no tracking.")
                    .font(DS.Text.body)
                    .foregroundStyle(DS.textSecondary)
                    .frame(maxWidth: 560, alignment: .leading)
                HStack(spacing: 10) {
                    Button { library.importGoodreads() } label: {
                        Label("Import from Goodreads", systemImage: "square.and.arrow.down")
                    }
                    .buttonStyle(PrimaryButtonStyle(fullWidth: false))
                    Button { app.go(.discover) } label: { Label("Discover Books", systemImage: "safari") }
                        .buttonStyle(GlassButtonStyle())
                    Button { library.presentAddBook() } label: { Label("Add Manually", systemImage: "plus") }
                        .buttonStyle(GlassButtonStyle())
                }
                Text("On Goodreads: My Books → Import and export → Export Library, then choose the downloaded CSV.")
                    .font(DS.Text.caption)
                    .foregroundStyle(DS.textTertiary)
            }
        }
    }
}

private struct ReadingCard: View {
    @EnvironmentObject var library: Library
    @EnvironmentObject var app: AppState
    let book: Book
    var selected = false
    @State private var showingUpdate = false
    @State private var page = ""

    var body: some View {
        let forecast = ReadingForecast.make(book: book, sessions: library.sessions(for: book.id))
        HStack(alignment: .top, spacing: 14) {
            CoverView(book: book).frame(width: 70)
            VStack(alignment: .leading, spacing: 4) {
                Text(book.title).font(.system(size: 14, weight: .semibold)).lineLimit(2)
                Text(book.authorLine).font(DS.Text.callout).foregroundStyle(DS.textSecondary).lineLimit(1)
                Spacer(minLength: 6)
                HStack(alignment: .firstTextBaseline) {
                    Text("\(Int(book.progress * 100))%")
                        .font(.system(size: 15, weight: .semibold, design: .rounded).monospacedDigit())
                    if book.progressProvenance == .loggedInFolio, let left = forecast.pagesRemaining {
                        Text("\(left) pages left").font(DS.Text.caption).foregroundStyle(DS.textSecondary)
                    }
                    Spacer()
                    if book.progressProvenance == .loggedInFolio {
                        Text(etaText(forecast)).font(DS.Text.caption).foregroundStyle(DS.textTertiary)
                    } else {
                        ProgressSourceLabel(book: book).font(DS.Text.caption).lineLimit(1)
                    }
                }
                ProgressBar(value: book.progress, tint: DS.statusReading)
                HStack(spacing: 6) {
                    Button("Update Page") { page = String(book.currentPage); showingUpdate = true }
                        .buttonStyle(GlassButtonStyle())
                        .popover(isPresented: $showingUpdate, arrowEdge: .bottom) { updateForm }
                    if library.activeSession?.bookID != book.id {
                        Button { library.startSession(book.id) } label: { Label("Read", systemImage: "play.fill") }
                            .buttonStyle(GlassButtonStyle())
                            .help("Start a timed reading session")
                    }
                    Spacer()
                }
                .padding(.top, 4)
            }
        }
        .frame(height: 118)
        .padding(14)
        .hoverGlass(selected: selected)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { app.openDetail(book.id) }
        .onTapGesture { app.open(book.id) }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(book.title), \(Int(book.progress * 100)) percent read")
    }

    private func etaText(_ f: ReadingForecast) -> String {
        switch f.confidence {
        case .insufficient: return book.pageCount == nil ? "" : "Finish date: needs more data"
        case .low: return f.finish.map { "≈ \($0.formatted(.dateTime.month(.abbreviated).day())) (rough)" } ?? ""
        case .good: return f.finish.map { "Finish ≈ \($0.formatted(.dateTime.month(.abbreviated).day()))" } ?? ""
        }
    }

    private var updateForm: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("What page are you on?").font(DS.Text.headline)
            HStack {
                TextField("Page", text: $page).textFieldStyle(GlassFieldStyle()).frame(width: 80).onSubmit(save)
                if let p = book.pageCount { Text("of \(p)").foregroundStyle(DS.textSecondary) }
            }
            HStack {
                Button("I finished it") { library.setStatus(book.id, .read); showingUpdate = false }
                    .buttonStyle(GhostButtonStyle())
                Spacer()
                Button("Save", action: save)
                    .buttonStyle(PrimaryButtonStyle(fullWidth: false))
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
        .frame(width: 270)
    }

    private func save() {
        if let p = page.intValue { library.logProgress(book.id, page: p) }
        showingUpdate = false
    }
}

/// Want-to-read queue. Drag a cover onto another to reorder.
private struct UpNextQueue: View {
    @EnvironmentObject var library: Library
    @EnvironmentObject var app: AppState
    @State private var targeted: UUID?

    var body: some View {
        let queue = Array(library.upNext.prefix(12))
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: "Up Next", subtitle: queue.isEmpty ? nil : "drag to reorder") {
                Button("See all") { app.show(.status(.wantToRead)) }.buttonStyle(GhostButtonStyle())
            }
            if queue.isEmpty {
                Text("Add books to Want to Read to build your queue.")
                    .font(DS.Text.body).foregroundStyle(DS.textSecondary)
            } else {
                ScrollView(.horizontal) {
                    HStack(alignment: .top, spacing: 16) {
                        ForEach(Array(queue.enumerated()), id: \.element.id) { i, book in
                            VStack(alignment: .leading, spacing: 6) {
                                CoverView(book: book)
                                    .frame(width: 92)
                                    .overlay(alignment: .topLeading) {
                                        Text("\(i + 1)")
                                            .font(.system(size: 10, weight: .bold, design: .rounded))
                                            .foregroundStyle(.white)
                                            .frame(width: 18, height: 18)
                                            .background(Circle().fill(.black.opacity(0.55)))
                                            .padding(5)
                                    }
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 4)
                                            .strokeBorder(targeted == book.id ? DS.accent : .clear, lineWidth: 2)
                                    )
                                Text(book.title).font(.system(size: 11.5, weight: .semibold)).lineLimit(2).frame(width: 92, alignment: .leading)
                            }
                            .contentShape(Rectangle())
                            .onTapGesture(count: 2) { app.openDetail(book.id) }
                            .onTapGesture { app.open(book.id) }
                            .contextMenu {
                                Button("Start Reading") { library.setStatus(book.id, .reading) }
                                Button("Move to Front") { library.moveInQueue(book.id, to: 0) }
                            }
                            .draggable(FolioDrag.book(book)) { CoverView(book: book).frame(width: 70) }
                            .dropDestination(for: FolioDrag.self) { items, _ in
                                guard let id = items.first(where: { $0.kind == .book })?.id, id != book.id else { return false }
                                Motion.perform { library.moveInQueue(id, to: i) }
                                return true
                            } isTargeted: { targeted = $0 ? book.id : (targeted == book.id ? nil : targeted) }
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

struct KnowledgeCard: View {
    @EnvironmentObject var app: AppState
    let ref: NoteRef

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(ref.note.kind.title, systemImage: ref.note.kind.symbol)
                .font(DS.Text.eyebrow).textCase(.uppercase).tracking(0.5)
                .foregroundStyle(ref.note.kind.isFromBook ? DS.statusReading : DS.accent)
            Text(ref.note.plainText)
                .font(ref.note.kind.isFromBook ? DS.serif(13.5).italic() : .system(size: 12.5))
                .lineSpacing(2)
                .lineLimit(5)
                .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 8) {
                CoverView(book: ref.book, size: "S").frame(width: 16)
                Text(ref.book.title).font(DS.Text.caption.weight(.medium)).lineLimit(1)
                if let loc = ref.note.locationLabel { Text(loc).font(DS.Text.caption).foregroundStyle(DS.textTertiary) }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .hoverGlass()
        .contentShape(Rectangle())
        .onTapGesture { app.openDetail(ref.book.id) }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
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
            HStack(spacing: 18) {
                ZStack {
                    ProgressRing(value: fraction, lineWidth: 9)
                    VStack(spacing: 0) {
                        Text("\(done)").font(.system(size: 24, weight: .semibold, design: .rounded).monospacedDigit())
                        if goal > 0 { Text("of \(goal)").font(DS.Text.micro).foregroundStyle(DS.textSecondary) }
                    }
                }
                .frame(width: 86, height: 86)
                VStack(alignment: .leading, spacing: 6) {
                    Text("\(String(year)) Reading Challenge").font(DS.Text.headline)
                    Text(paceMessage(done: done, goal: goal)).font(DS.Text.callout).foregroundStyle(DS.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Stepper(value: Binding(get: { goal }, set: { library.goals[year] = max(0, $0) }), in: 0...500) {
                        Text(goal == 0 ? "Set a goal" : "Goal: \(goal) books").font(DS.Text.callout)
                    }
                    .padding(.top, 2)
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
        if diff < 0 { return "\(-diff) book\(diff == -1 ? "" : "s") behind schedule." }
        return "Right on track."
    }
}
