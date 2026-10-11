import SwiftUI

enum SortKey: String, CaseIterable, Identifiable {
    case added = "Date Added", title = "Title", author = "Author", rating = "My Rating", finished = "Date Read", pages = "Length"
    var id: String { rawValue }

    var comparator: KeyPathComparator<Book> {
        switch self {
        case .added: KeyPathComparator(\Book.dateAdded, order: .reverse)
        case .title: KeyPathComparator(\Book.sortTitle)
        case .author: KeyPathComparator(\Book.sortAuthor)
        case .rating: KeyPathComparator(\Book.ratingValue, order: .reverse)
        case .finished: KeyPathComparator(\Book.finishedValue, order: .reverse)
        case .pages: KeyPathComparator(\Book.pagesValue, order: .reverse)
        }
    }
}

enum ViewMode: String, CaseIterable, Identifiable {
    case board, grid, table
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .board: "rectangle.split.3x1"
        case .grid: "square.grid.2x2"
        case .table: "list.bullet"
        }
    }
    var title: String { rawValue.capitalized }
}

enum QuickFilter: String, CaseIterable, Identifiable {
    case loved = "4★ & up", unrated = "Unrated", favorites = "Favourites", thisYear = "Read this year",
         hasNotes = "Has notes", long = "500+ pages", short = "Under 250 pages"
    var id: String { rawValue }

    func matches(_ b: Book) -> Bool {
        switch self {
        case .loved: b.ratingValue >= 4
        case .unrated: b.rating == nil
        case .favorites: b.favorite
        case .thisYear: b.dateFinished.map { Calendar.current.isDate($0, equalTo: Date(), toGranularity: .year) } ?? false
        case .hasNotes: !b.notes.isEmpty || !b.review.isEmpty
        case .long: b.pagesValue >= 500
        case .short: b.pageCount.map { $0 < 250 } ?? false
        }
    }
}

struct LibraryView: View {
    @EnvironmentObject var library: Library
    @EnvironmentObject var app: AppState
    @AppStorage("library.mode") private var mode = ViewMode.board
    @AppStorage("library.sort") private var sortKey = SortKey.added
    @State private var filters = Set<QuickFilter>()
    @State private var tableSort = [SortKey.added.comparator]
    @State private var tableSelection = Set<UUID>()
    @State private var pendingDelete: Set<UUID> = []

    private var title: String {
        switch app.scope {
        case .all: "All Books"
        case .favorites: "Favourites"
        case .shelf(let s): s.title
        case .tag(let t): t.replacingOccurrences(of: "-", with: " ").capitalized
        }
    }

    private func inScope(_ b: Book) -> Bool {
        switch app.scope {
        case .all: true
        case .favorites: b.favorite
        case .shelf(let s): b.status == s
        case .tag(let t): b.tags.contains(t)
        }
    }

    private var isStatusScope: Bool { if case .shelf = app.scope { true } else { false } }
    private var effectiveMode: ViewMode { mode == .board && isStatusScope ? .grid : mode }

    private var books: [Book] {
        let q = app.search.trimmingCharacters(in: .whitespaces).lowercased()
        return library.books
            .filter(inScope)
            .filter { q.isEmpty || $0.title.lowercased().contains(q) || $0.authorLine.lowercased().contains(q) || $0.tags.contains { $0.contains(q) } }
            .filter { b in filters.allSatisfy { $0.matches(b) } }
            .sorted(using: effectiveMode == .table ? tableSort : [sortKey.comparator])
    }

    var body: some View {
        let books = books
        VStack(alignment: .leading, spacing: 0) {
            header(count: books.count)
                .padding(.horizontal, 28)
                .padding(.top, 22)
                .padding(.bottom, 14)
            if library.books.filter(inScope).isEmpty {
                emptyState
            } else {
                switch effectiveMode {
                case .board: board(books)
                case .grid: grid(books)
                case .table: table(books)
                }
            }
        }
        .confirmationDialog("Remove \(pendingDelete.count) book\(pendingDelete.count == 1 ? "" : "s") from your library?",
                            isPresented: Binding(get: { !pendingDelete.isEmpty }, set: { if !$0 { pendingDelete = [] } })) {
            Button("Remove", role: .destructive) {
                if let sel = app.selectedBook, pendingDelete.contains(sel) { app.selectedBook = nil }
                library.delete(pendingDelete)
                pendingDelete = []
            }
        } message: {
            Text("Ratings, reviews and notes for these books will be deleted.")
        }
    }

    // MARK: Header

    private func header(count: Int) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            PageHeader(title: title, caption: "Total: \(count)") {
                GlassSegmented(selection: Binding(get: { effectiveMode }, set: { mode = $0 }),
                               options: ViewMode.allCases,
                               disabled: { $0 == .board && isStatusScope }) { m in
                    Image(systemName: m.symbol)
                        .help(m == .board && isStatusScope ? "Board shows all shelves. Open All Books to use it." : m.title)
                        .accessibilityLabel(m.title)
                }
            }
            HStack(spacing: 6) {
                Menu {
                    ForEach(QuickFilter.allCases) { f in
                        Toggle(f.rawValue, isOn: Binding(
                            get: { filters.contains(f) },
                            set: { on in if on { filters.insert(f) } else { filters.remove(f) } }))
                    }
                    if !filters.isEmpty {
                        Divider()
                        Button("Clear Filters") { filters = [] }
                    }
                } label: {
                    Label("Filter", systemImage: "plus").font(.system(size: 12))
                }
                .menuStyle(.button)
                .buttonStyle(GlassButtonStyle())
                .menuIndicator(.hidden)
                .fixedSize()

                ForEach(QuickFilter.allCases.filter(filters.contains)) { f in
                    Button { filters.remove(f) } label: {
                        HStack(spacing: 4) {
                            Text(f.rawValue)
                            Image(systemName: "xmark").font(.system(size: 8, weight: .bold))
                        }
                    }
                    .buttonStyle(PillButtonStyle(selected: true))
                }
                Spacer()
                if effectiveMode != .table {
                    Menu {
                        Picker("Sort By", selection: $sortKey) {
                            ForEach(SortKey.allCases) { Text($0.rawValue).tag($0) }
                        }
                        .pickerStyle(.inline)
                    } label: {
                        Label(sortKey.rawValue, systemImage: "arrow.up.arrow.down").font(.system(size: 12))
                    }
                    .menuStyle(.button)
                    .buttonStyle(GlassButtonStyle())
                    .menuIndicator(.hidden)
                    .fixedSize()
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "books.vertical")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(DS.textTertiary)
            Text("No books here yet").font(DS.serif(22, .medium))
            Text("Find books in Discover, add one by hand, or bring your whole Goodreads history.")
                .foregroundStyle(DS.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
            HStack {
                Button("Import from Goodreads…") { library.importGoodreads() }.buttonStyle(GlassButtonStyle())
                Button("Discover Books") { app.go(.discover) }.buttonStyle(GlassButtonStyle())
            }
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.bottom, 60)
    }

    // MARK: Board

    private func board(_ books: [Book]) -> some View {
        ScrollView(.horizontal) {
            HStack(alignment: .top, spacing: 14) {
                ForEach([ReadingStatus.wantToRead, .reading, .read, .dnf]) { status in
                    BoardColumn(status: status, books: books.filter { $0.status == status }, menu: menu)
                }
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 18)
        }
        .scrollIndicators(.automatic)
    }

    // MARK: Grid

    private func grid(_ books: [Book]) -> some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 138, maximum: 172), spacing: 24, alignment: .top)], spacing: 28) {
                ForEach(books) { book in
                    BookTile(book: book, selected: app.selectedBook == book.id)
                        .onTapGesture { app.open(book.id) }
                        .contextMenu { menu(for: [book.id]) }
                        .draggable(book.id.uuidString)
                }
            }
            .padding(.horizontal, 28)
            .padding(.top, 6)
            .padding(.bottom, 28)
        }
    }

    // MARK: Table

    private func table(_ books: [Book]) -> some View {
        Table(books, selection: $tableSelection, sortOrder: $tableSort) {
            TableColumn("Title", value: \.sortTitle) { b in
                HStack(spacing: 10) {
                    CoverView(book: b, size: "S").frame(width: 22)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(b.title).fontWeight(.medium).lineLimit(1)
                        if b.status == .reading, b.pageCount != nil {
                            ProgressBar(value: b.progress, height: 3).frame(maxWidth: 110)
                        }
                    }
                }
                .padding(.vertical, 3)
            }
            .width(min: 180, ideal: 260)
            TableColumn("Author", value: \.sortAuthor) { Text($0.authorLine).lineLimit(1).foregroundStyle(DS.textSecondary) }
                .width(min: 100, ideal: 150)
            TableColumn("Rating", value: \.ratingValue) { StarRating(value: $0.rating) }
                .width(80)
            TableColumn("Shelf", value: \.statusValue) { StatusBadge(status: $0.status) }
                .width(90)
            TableColumn("Pages", value: \.pagesValue) { Text($0.pageCount.map(String.init) ?? "—").monospacedDigit() }
                .width(50)
            TableColumn("Date Read", value: \.finishedValue) { Text($0.dateFinished?.numericString ?? "—") }
                .width(84)
        }
        .scrollContentBackground(.hidden)
        .alternatingRowBackgrounds(.disabled)
        .font(.system(size: 12))
        .padding(.horizontal, 16)
        .contextMenu(forSelectionType: UUID.self) { ids in
            menu(for: ids)
        } primaryAction: { ids in
            if let id = ids.first { app.open(id) }
        }
        .onChange(of: tableSelection) { _, sel in
            if sel.count == 1, let id = sel.first { app.open(id) }
        }
        .onDeleteCommand { pendingDelete = tableSelection }
    }

    @ViewBuilder
    func menu(for ids: Set<UUID>) -> some View {
        Menu("Move to Shelf") {
            ForEach(ReadingStatus.allCases) { status in
                Button { ids.forEach { library.setStatus($0, status) } } label: {
                    Label(status.title, systemImage: status.symbol)
                }
            }
        }
        Button("Toggle Favourite") { ids.forEach { id in library.modify(id) { $0.favorite.toggle() } } }
        Divider()
        Button("Remove from Library…", role: .destructive) { pendingDelete = ids }
    }
}

// MARK: - Board pieces

private struct BoardColumn<M: View>: View {
    @EnvironmentObject var library: Library
    @EnvironmentObject var app: AppState
    let status: ReadingStatus
    let books: [Book]
    let menu: (Set<UUID>) -> M
    @State private var targeted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text(status.boardTitle)
                    .font(.system(size: 12.5, weight: .semibold))
                Spacer()
                Image(systemName: "line.3.horizontal.decrease")
                    .font(.system(size: 9))
                    .foregroundStyle(DS.textTertiary)
                Text("\(books.count)")
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(DS.textSecondary)
            }
            .padding(.horizontal, 4)

            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(books) { book in
                        BoardCard(book: book, selected: app.selectedBook == book.id)
                            .onTapGesture { app.open(book.id) }
                            .contextMenu { menu([book.id]) }
                            .draggable(book.id.uuidString) {
                                BoardCard(book: book, selected: true).frame(width: 240)
                            }
                    }
                    Button { library.presentAddBook(status) } label: {
                        Label("Add a Book", systemImage: "plus")
                            .font(.system(size: 11.5))
                            .foregroundStyle(DS.textSecondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .background(RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous)
                                .strokeBorder(DS.strokeStrong, style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .padding(8)
            }
            .scrollIndicators(.never)
            .background(
                RoundedRectangle(cornerRadius: DS.Radius.panel, style: .continuous)
                    .fill(targeted ? DS.selection : DS.well)
            )
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.panel, style: .continuous)
                    .strokeBorder(targeted ? DS.accent.opacity(0.7) : DS.stroke.opacity(0.6), style: StrokeStyle(lineWidth: targeted ? 1.5 : 1, dash: targeted ? [6, 4] : []))
            )
        }
        .frame(width: 240)
        .frame(maxHeight: .infinity, alignment: .top)
        .dropDestination(for: String.self) { items, _ in
            let ids = items.compactMap(UUID.init(uuidString:))
            guard !ids.isEmpty else { return false }
            withAnimation(.snappy(duration: 0.25)) { ids.forEach { library.setStatus($0, status) } }
            return true
        } isTargeted: { targeted = $0 }
        .scaleEffect(targeted && !Motion.reduceMotion ? 1.01 : 1)
        .motion(Motion.gentle, value: targeted)
    }
}

struct BoardCard: View {
    @EnvironmentObject var library: Library
    let book: Book
    var selected = false
    @State private var hovering = false

    private var dateLine: String? {
        switch book.status {
        case .read: book.dateFinished.map { "Completed \($0.numericString)" }
        case .reading: book.dateStarted.map { "Started \($0.numericString)" }
        case .wantToRead: "Added \(book.dateAdded.numericString)"
        case .dnf: book.dateStarted.map { "Started \($0.numericString)" } ?? "Added \(book.dateAdded.numericString)"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .top, spacing: 11) {
                CoverView(book: book).frame(width: 50)
                VStack(alignment: .leading, spacing: 3) {
                    if let r = book.rating { StarRating(value: r, size: 8.5) }
                    if let dateLine {
                        Text(dateLine).font(.system(size: 9.5)).foregroundStyle(DS.textSecondary)
                    }
                    Text(book.title)
                        .font(.system(size: 12.5, weight: .semibold))
                        .lineLimit(2)
                        .padding(.top, 1)
                    Text(book.authorLine)
                        .font(.system(size: 10.5))
                        .foregroundStyle(DS.textSecondary)
                        .lineLimit(1)
                    if book.status == .reading {
                        HStack(spacing: 6) {
                            ProgressBar(value: book.progress, height: 3)
                            Text("\(Int(book.progress * 100))%")
                                .font(.system(size: 9).monospacedDigit())
                                .foregroundStyle(DS.textSecondary)
                        }
                        .padding(.top, 4)
                    }
                }
                .padding(.trailing, 14)
                Spacer(minLength: 0)
            }
            let chips = book.chips
            if !chips.isEmpty {
                FlowLayout(spacing: 4) {
                    ForEach(chips, id: \.self) { Chip(text: $0) }
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glass(.card, cornerRadius: DS.Radius.card - 2, hovering: hovering, selected: selected)
        .overlay(alignment: .topTrailing) {
            Button { library.modify(book.id) { $0.favorite.toggle() } } label: {
                Image(systemName: book.favorite ? "heart.fill" : "heart")
                    .font(.system(size: 11))
                    .foregroundStyle(book.favorite ? DS.favorite : DS.textTertiary)
            }
            .buttonStyle(.plain)
            .padding(8)
            .help(book.favorite ? "Remove from Favourites" : "Add to Favourites")
        }
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .motion(Motion.gentle, value: hovering)
    }
}

struct BookTile: View {
    let book: Book
    var selected = false
    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            CoverView(book: book)
                .overlay(alignment: .topTrailing) {
                    if book.favorite {
                        Image(systemName: "heart.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(DS.onAccent)
                            .padding(5)
                            .background(DS.favorite, in: Circle())
                            .padding(6)
                    }
                }
                .padding(3)
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(selected ? DS.accent : .clear, lineWidth: 2)
                )
                .offset(y: hovering ? -3 : 0)
                .animation(.spring(duration: 0.25), value: hovering)
            Text(book.title)
                .font(.system(size: 12.5, weight: .semibold))
                .lineLimit(2)
                .padding(.top, 2)
            Text(book.authorLine)
                .font(.system(size: 11))
                .foregroundStyle(DS.textSecondary)
                .lineLimit(1)
            if book.status == .reading {
                ProgressBar(value: book.progress, height: 3).padding(.top, 2)
            } else if let rating = book.rating {
                StarRating(value: rating, size: 9)
            }
        }
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
    }
}
