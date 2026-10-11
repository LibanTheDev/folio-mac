import SwiftUI

enum ViewMode: String, CaseIterable, Identifiable {
    case board, grid, list
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .board: "rectangle.split.3x1"
        case .grid: "square.grid.2x2"
        case .list: "list.bullet"
        }
    }
    var title: String { rawValue.capitalized }
}

struct LibraryView: View {
    @EnvironmentObject var library: Library
    @EnvironmentObject var app: AppState
    @AppStorage("library.mode") private var mode = ViewMode.grid
    @AppStorage("library.sort") private var sortKey = SortKey.added
    @AppStorage("library.coverSize") private var coverSize = 150.0
    @State private var filter = LibraryFilter()
    @State private var showingFilters = false
    @State private var tableSort = [SortKey.added.comparator]
    @State private var tableSelection = Set<UUID>()
    @State private var pendingDelete: Set<UUID> = []

    private var currentShelf: Shelf? {
        if case .shelf(let id) = app.scope { return library.shelf(id) }
        return nil
    }

    private var title: String {
        switch app.scope {
        case .all: "All Books"
        case .favorites: "Favourites"
        case .status(let s): s.title
        case .tag(let t): "#" + t.replacingOccurrences(of: "-", with: " ")
        case .shelf: currentShelf?.name ?? "Shelf"
        }
    }

    private var caption: String {
        switch app.scope {
        case .shelf: currentShelf?.kind == .smart ? "Smart shelf" : "Collection"
        case .tag: "Tag"
        default: "Library"
        }
    }

    private var scoped: [Book] {
        switch app.scope {
        case .all: library.books
        case .favorites: library.books.filter(\.favorite)
        case .status(let s): library.books(in: s)
        case .tag(let t): library.books.filter { $0.tags.contains(t) }
        case .shelf: currentShelf.map { library.books(on: $0) } ?? []
        }
    }

    private var isStatusScope: Bool { if case .status = app.scope { true } else { false } }
    private var effectiveMode: ViewMode { mode == .board && isStatusScope ? .grid : mode }
    private var canUseManualOrder: Bool { currentShelf?.kind == .manual }

    private var books: [Book] {
        let q = app.search.trimmingCharacters(in: .whitespaces).lowercased()
        let now = Date()
        let filtered = scoped
            .filter { q.isEmpty || $0.title.lowercased().contains(q) || $0.authorLine.lowercased().contains(q) || $0.tags.contains { $0.contains(q) } }
            .filter { filter.matches($0, shelves: library.shelves, now: now) }
        if effectiveMode == .list { return filtered.sorted(using: tableSort) }
        if sortKey == .manual, canUseManualOrder { return filtered }  // already in shelf order
        return filtered.sorted(using: [sortKey == .manual ? SortKey.added.comparator : sortKey.comparator])
    }

    var body: some View {
        let books = books
        VStack(alignment: .leading, spacing: 0) {
            header(count: books.count)
                .padding(.horizontal, DS.Space.page)
                .padding(.top, 10)
                .padding(.bottom, 14)
            if scoped.isEmpty {
                emptyState
            } else if books.isEmpty {
                EmptyStateView(icon: "line.3.horizontal.decrease.circle", title: "No matches",
                               message: "No books match the current filters or search.") {
                    Button("Clear Filters") { filter = LibraryFilter(); app.search = "" }
                        .buttonStyle(GlassButtonStyle())
                }
            } else {
                switch effectiveMode {
                case .board: board(books)
                case .grid: grid(books)
                case .list: table(books)
                }
            }
        }
        .onChange(of: app.scope) { filter = LibraryFilter() }
        .confirmationDialog("Remove \(pendingDelete.count) book\(pendingDelete.count == 1 ? "" : "s") from your library?",
                            isPresented: Binding(get: { !pendingDelete.isEmpty }, set: { if !$0 { pendingDelete = [] } })) {
            Button("Remove", role: .destructive) {
                if let sel = app.selectedBook, pendingDelete.contains(sel) { app.selectedBook = nil }
                library.delete(pendingDelete)
                pendingDelete = []
            }
        } message: {
            Text("Ratings, reviews, notes and reading sessions for these books will be deleted.")
        }
    }

    // MARK: Header

    private func header(count: Int) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            PageHeader(title: title, caption: "\(caption) · \(count) book\(count == 1 ? "" : "s")") {
                HStack(spacing: 8) {
                    if let shelf = currentShelf {
                        Button { app.editingShelf = shelf } label: { Label("Edit Shelf", systemImage: "slider.horizontal.3") }
                            .buttonStyle(GlassButtonStyle())
                    }
                    GlassSegmented(selection: Binding(get: { effectiveMode }, set: { mode = $0 }),
                                   options: ViewMode.allCases,
                                   disabled: { $0 == .board && isStatusScope }) { m in
                        Image(systemName: m.symbol)
                            .help(m == .board && isStatusScope ? "The board shows every status. Open All Books to use it." : m.title)
                            .accessibilityLabel(m.title)
                    }
                }
            }
            HStack(spacing: 6) {
                Button { showingFilters.toggle() } label: {
                    Label(filter.isEmpty ? "Filter" : "Filters", systemImage: "line.3.horizontal.decrease")
                }
                .buttonStyle(GlassButtonStyle())
                .popover(isPresented: $showingFilters, arrowEdge: .bottom) {
                    FilterPanel(filter: $filter).environmentObject(library)
                }
                ScrollView(.horizontal) {
                    HStack(spacing: 5) {
                        ForEach(filter.tokens(shelfName: { library.shelf($0)?.name })) { token in
                            Button { Motion.perform { filter.remove(token.id) } } label: {
                                HStack(spacing: 4) {
                                    Text(token.label)
                                    Image(systemName: "xmark").font(.system(size: 8, weight: .bold))
                                }
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(DS.accent)
                                .padding(.horizontal, 8).padding(.vertical, 4)
                                .background(Capsule().fill(DS.selection))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Remove filter \(token.label)")
                        }
                        if !filter.isEmpty {
                            Button("Clear") { Motion.perform { filter = LibraryFilter() } }
                                .buttonStyle(GhostButtonStyle())
                        }
                    }
                }
                .scrollIndicators(.never)
                Spacer(minLength: 8)
                if effectiveMode == .grid {
                    HStack(spacing: 6) {
                        Image(systemName: "photo").font(.system(size: 9)).foregroundStyle(DS.textTertiary)
                        Slider(value: $coverSize, in: 100...230)
                            .controlSize(.mini)
                            .frame(width: 90)
                            .accessibilityLabel("Cover size")
                        Image(systemName: "photo").font(.system(size: 13)).foregroundStyle(DS.textTertiary)
                    }
                    .help("Cover size")
                }
                if effectiveMode != .list {
                    Menu {
                        Picker("Sort By", selection: $sortKey) {
                            ForEach(SortKey.allCases.filter { $0 != .manual || canUseManualOrder }) { Text($0.rawValue).tag($0) }
                        }
                        .pickerStyle(.inline)
                    } label: {
                        Label(sortKey == .manual && !canUseManualOrder ? SortKey.added.rawValue : sortKey.rawValue,
                              systemImage: "arrow.up.arrow.down")
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
        Group {
            if let shelf = currentShelf {
                EmptyStateView(icon: shelf.kind == .smart ? "sparkles" : "tray",
                               title: shelf.kind == .smart ? "No books match yet" : "This collection is empty",
                               message: shelf.kind == .smart
                                   ? "Smart shelves update automatically as your library changes. Adjust the rules to widen it."
                                   : "Drag books onto this shelf in the sidebar, or use “Add to Collection” from a book's menu.") {
                    Button("Edit Shelf") { app.editingShelf = shelf }.buttonStyle(GlassButtonStyle())
                }
            } else {
                EmptyStateView(icon: "books.vertical", title: "No books here yet",
                               message: "Find books in Discover, add one by hand, or bring your whole Goodreads history.") {
                    Button("Import from Goodreads…") { library.importGoodreads() }.buttonStyle(GlassButtonStyle())
                    Button("Discover Books") { app.go(.discover) }.buttonStyle(GlassButtonStyle())
                }
            }
        }
    }

    // MARK: Board

    private func board(_ books: [Book]) -> some View {
        ScrollView(.horizontal) {
            HStack(alignment: .top, spacing: 14) {
                ForEach([ReadingStatus.wantToRead, .reading, .read, .dnf]) { status in
                    BoardColumn(status: status, books: books.filter { $0.status == status },
                                menu: { ids in BookContextMenu(ids: ids, shelf: currentShelf, pendingDelete: $pendingDelete) })
                }
            }
            .padding(.horizontal, DS.Space.page)
            .padding(.bottom, 18)
        }
    }

    // MARK: Grid

    private func grid(_ books: [Book]) -> some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: coverSize, maximum: coverSize * 1.2), spacing: 24, alignment: .top)], spacing: 28) {
                ForEach(books) { book in
                    BookTile(book: book, selected: app.selectedBook == book.id)
                        .onTapGesture(count: 2) { app.openDetail(book.id) }
                        .onTapGesture { app.open(book.id) }
                        .contextMenu { BookContextMenu(ids: [book.id], shelf: currentShelf, pendingDelete: $pendingDelete) }
                        .draggable(FolioDrag.book(book)) {
                            CoverView(book: book).frame(width: 80)
                        }
                }
            }
            .padding(.horizontal, DS.Space.page)
            .padding(.top, 6)
            .padding(.bottom, 28)
        }
    }

    // MARK: List

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
            TableColumn("Status", value: \.statusValue) { StatusBadge(status: $0.status) }
                .width(96)
            TableColumn("Pages", value: \.pagesValue) { Text($0.pageCount.map(String.init) ?? "—").monospacedDigit() }
                .width(50)
            TableColumn("Published", value: \.publishedValue) { Text($0.publishYear.map(String.init) ?? "—").monospacedDigit() }
                .width(66)
            TableColumn("Completed", value: \.finishedValue) { Text($0.dateFinished?.numericString ?? "—") }
                .width(84)
            TableColumn("Added", value: \.dateAdded) { Text($0.dateAdded.numericString) }
                .width(84)
        }
        .scrollContentBackground(.hidden)
        .alternatingRowBackgrounds(.disabled)
        .font(.system(size: 12))
        .padding(.horizontal, 16)
        .contextMenu(forSelectionType: UUID.self) { ids in
            BookContextMenu(ids: ids, shelf: currentShelf, pendingDelete: $pendingDelete)
        } primaryAction: { ids in
            if let id = ids.first { app.openDetail(id) }
        }
        .onChange(of: tableSelection) { _, sel in
            if sel.count == 1, let id = sel.first { app.open(id) }
        }
        .onDeleteCommand { pendingDelete = tableSelection }
    }
}

// MARK: - Context menu

/// Actions available on one or more books, used everywhere books appear.
struct BookContextMenu: View {
    @EnvironmentObject var library: Library
    @EnvironmentObject var app: AppState
    let ids: Set<UUID>
    var shelf: Shelf?
    @Binding var pendingDelete: Set<UUID>

    var body: some View {
        if ids.count == 1, let id = ids.first {
            Button("Open") { app.openDetail(id) }
            Button("Show in Inspector") { app.open(id) }
            if library.book(id)?.status != .read || library.activeSession?.bookID != id {
                Button("Start Reading Session") { library.startSession(id) }
                    .disabled(library.activeSession?.bookID == id)
            }
            Divider()
        }
        Menu("Set Status") {
            ForEach(ReadingStatus.allCases) { status in
                Button { ids.forEach { library.setStatus($0, status) } } label: {
                    Label(status.title, systemImage: status.symbol)
                }
            }
        }
        Menu("Add to Collection") {
            let manual = library.shelves.filter { $0.kind == .manual }
            ForEach(manual) { s in
                Button(s.name) { library.add(Array(ids), toShelf: s.id) }
            }
            if !manual.isEmpty { Divider() }
            Button("New Collection…") {
                app.editingShelf = Shelf(name: "", kind: .manual, bookIDs: Array(ids))
            }
        }
        if let shelf, shelf.kind == .manual {
            Button("Remove from “\(shelf.name)”") { library.remove(Array(ids), fromShelf: shelf.id) }
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
    @ViewBuilder let menu: (Set<UUID>) -> M
    @State private var targeted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Circle().fill(status.tint).frame(width: 7, height: 7)
                Text(status.boardTitle).font(DS.Text.headline)
                Spacer()
                Text("\(books.count)")
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(DS.textTertiary)
            }
            .padding(.horizontal, 6)

            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(books) { book in
                        BoardCard(book: book, selected: app.selectedBook == book.id)
                            .onTapGesture(count: 2) { app.openDetail(book.id) }
                            .onTapGesture { app.open(book.id) }
                            .contextMenu { menu([book.id]) }
                            .draggable(FolioDrag.book(book)) {
                                BoardCard(book: book, selected: true).frame(width: 240)
                            }
                    }
                    Button { library.presentAddBook(status) } label: {
                        Label("Add a Book", systemImage: "plus")
                            .font(DS.Text.caption)
                            .foregroundStyle(DS.textTertiary)
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
                    .strokeBorder(targeted ? DS.accent.opacity(0.7) : DS.stroke.opacity(0.6),
                                  style: StrokeStyle(lineWidth: targeted ? 1.5 : 1, dash: targeted ? [6, 4] : []))
            )
        }
        .frame(width: 244)
        .frame(maxHeight: .infinity, alignment: .top)
        .dropDestination(for: FolioDrag.self) { items, _ in
            let ids = items.filter { $0.kind == .book }.map(\.id)
            guard !ids.isEmpty else { return false }
            Motion.perform { ids.forEach { library.setStatus($0, status) } }
            return true
        } isTargeted: { targeted = $0 }
        .scaleEffect(targeted && !Motion.reduceMotion ? 1.01 : 1)
        .motion(Motion.gentle, value: targeted)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(status.boardTitle), \(books.count) books")
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
                CoverView(book: book).frame(width: 48)
                VStack(alignment: .leading, spacing: 3) {
                    if let r = book.rating { StarRating(value: r, size: 8.5) }
                    if let dateLine {
                        Text(dateLine).font(DS.Text.micro).foregroundStyle(DS.textTertiary)
                    }
                    Text(book.title)
                        .font(.system(size: 12.5, weight: .semibold))
                        .lineLimit(2)
                        .padding(.top, 1)
                    Text(book.authorLine)
                        .font(DS.Text.caption)
                        .foregroundStyle(DS.textSecondary)
                        .lineLimit(1)
                    if book.status == .reading {
                        HStack(spacing: 6) {
                            ProgressBar(value: book.progress, tint: DS.statusReading, height: 3)
                            Text("\(Int(book.progress * 100))%")
                                .font(.system(size: 9).monospacedDigit())
                                .foregroundStyle(DS.textTertiary)
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
            FavoriteButton(book: book, size: 11).padding(8)
        }
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .motion(Motion.gentle, value: hovering)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }
}

struct FavoriteButton: View {
    @EnvironmentObject var library: Library
    let book: Book
    var size: CGFloat = 13

    var body: some View {
        Button { library.modify(book.id) { $0.favorite.toggle() } } label: {
            Image(systemName: book.favorite ? "heart.fill" : "heart")
                .font(.system(size: size))
                .foregroundStyle(book.favorite ? DS.favorite : DS.textTertiary)
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(.plain)
        .help(book.favorite ? "Remove from Favourites" : "Add to Favourites")
        .accessibilityLabel(book.favorite ? "Remove from Favourites" : "Add to Favourites")
    }
}

/// Cover-first tile that reads as a physical book on a shelf.
struct BookTile: View {
    let book: Book
    var selected = false
    @State private var hovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            CoverView(book: book)
                .overlay(alignment: .topTrailing) {
                    if book.favorite {
                        Image(systemName: "heart.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(.white)
                            .padding(5)
                            .background(Circle().fill(DS.favorite))
                            .padding(6)
                    }
                }
                .overlay(alignment: .bottom) {
                    if book.status == .reading {
                        ProgressBar(value: book.progress, tint: DS.statusReading, height: 3)
                            .padding(6)
                    }
                }
                .padding(3)
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .strokeBorder(selected ? DS.accent : .clear, lineWidth: 2)
                )
                .shadow(color: .black.opacity(hovering ? 0.22 : 0), radius: 12, y: 8)
                .rotation3DEffect(.degrees(hovering && !reduceMotion ? 4 : 0), axis: (x: 0, y: 1, z: 0), anchor: .leading)
                .offset(y: hovering && !reduceMotion ? -4 : 0)
                .motion(Motion.spring, value: hovering)
            Text(book.title)
                .font(.system(size: 12.5, weight: .semibold))
                .lineLimit(2)
                .padding(.top, 2)
            Text(book.authorLine)
                .font(DS.Text.caption)
                .foregroundStyle(DS.textSecondary)
                .lineLimit(1)
            if let rating = book.rating {
                StarRating(value: rating, size: 9)
            }
        }
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }
}
