import SwiftUI

enum Page: String, CaseIterable, Identifiable {
    case home = "Home", books = "My Books", discover = "Discover", stats = "Stats"
    var id: String { rawValue }
}

/// What "My Books" is showing.
enum Scope: Hashable {
    case all, favorites
    case shelf(ReadingStatus)
    case tag(String)
}

@MainActor
final class AppState: ObservableObject {
    @Published var page: Page = .home
    @Published var scope: Scope = .all
    @Published var selectedBook: UUID?
    @Published var inspectorShown = true
    @Published var search = ""
    @Published var searchFocusRequests = 0

    func go(_ page: Page) { self.page = page }

    func show(_ scope: Scope) {
        self.scope = scope
        page = .books
    }

    func open(_ id: UUID) {
        withAnimation(.snappy(duration: 0.25)) {
            selectedBook = id
            inspectorShown = true
        }
    }

    func toggleInspector() {
        withAnimation(.snappy(duration: 0.25)) { inspectorShown.toggle() }
    }
}

struct ContentView: View {
    @EnvironmentObject var library: Library
    @EnvironmentObject var app: AppState

    var body: some View {
        HStack(spacing: 0) {
            SidebarView()
                .frame(width: 232)
            Rectangle().fill(Theme.border).frame(width: 1)
            VStack(spacing: 0) {
                TopBar()
                Rectangle().fill(Theme.border).frame(height: 1)
                page
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .background(Theme.canvas)
            if app.inspectorShown, let id = app.selectedBook, library.book(id) != nil {
                Rectangle().fill(Theme.border).frame(width: 1)
                InspectorView(id: id)
                    .frame(width: 330)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .background(Theme.canvas)
        .foregroundStyle(Theme.ink)
        .tint(Theme.accent)
        .ignoresSafeArea(.container, edges: .top)
        .environment(\.openBook) { app.open($0) }
        .onChange(of: app.search) { _, new in
            if !new.isEmpty, app.page == .home || app.page == .stats { app.show(.all) }
        }
        .sheet(isPresented: $library.showingAddBook) {
            AddBookSheet(initialStatus: library.addBookStatus)
                .environmentObject(library)
        }
        .alert("Folio", isPresented: Binding(get: { library.alertMessage != nil }, set: { if !$0 { library.alertMessage = nil } })) {
            Button("OK") { library.alertMessage = nil }
        } message: {
            Text(library.alertMessage ?? "")
        }
    }

    @ViewBuilder private var page: some View {
        switch app.page {
        case .home: HomeView()
        case .books: LibraryView()
        case .discover: DiscoverView()
        case .stats: StatsView()
        }
    }
}

// MARK: - Top bar

struct TopBar: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject var library: Library
    @State private var searchOpen = false
    @FocusState private var searchFocused: Bool

    var body: some View {
        ZStack {
            HStack(spacing: 4) {
                ForEach(Page.allCases) { page in
                    Button(page.rawValue) { app.go(page) }
                        .buttonStyle(PillButtonStyle(selected: app.page == page))
                }
            }
            HStack(spacing: 6) {
                Spacer()
                if searchOpen || !app.search.isEmpty {
                    HStack(spacing: 6) {
                        Image(systemName: "magnifyingglass").font(.system(size: 11)).foregroundStyle(Theme.muted)
                        TextField(app.page == .discover ? "Search Open Library" : "Search your books", text: $app.search)
                            .textFieldStyle(.plain)
                            .font(.system(size: 12))
                            .focused($searchFocused)
                            .onExitCommand { app.search = ""; searchOpen = false }
                        if !app.search.isEmpty {
                            Button { app.search = "" } label: { Image(systemName: "xmark.circle.fill") }
                                .buttonStyle(.plain)
                                .foregroundStyle(Theme.faint)
                        }
                    }
                    .padding(.horizontal, 9)
                    .frame(width: 210, height: 26)
                    .background(Theme.card, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(Theme.border))
                    .transition(.opacity.combined(with: .scale(scale: 0.95, anchor: .trailing)))
                } else {
                    Button { openSearch() } label: { Image(systemName: "magnifyingglass") }
                        .buttonStyle(IconButtonStyle())
                        .help("Search (⌘F)")
                }
                if app.selectedBook != nil {
                    Button { app.toggleInspector() } label: { Image(systemName: "sidebar.right") }
                        .buttonStyle(IconButtonStyle(selected: app.inspectorShown))
                        .help("Toggle inspector (⌥⌘I)")
                }
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 52)
        .animation(.snappy(duration: 0.2), value: searchOpen)
        .onChange(of: app.searchFocusRequests) { openSearch() }
        .onChange(of: searchFocused) { _, focused in
            if !focused, app.search.isEmpty { searchOpen = false }
        }
    }

    private func openSearch() {
        searchOpen = true
        DispatchQueue.main.async { searchFocused = true }
    }
}

// MARK: - Sidebar

struct SidebarView: View {
    @EnvironmentObject var library: Library
    @EnvironmentObject var app: AppState
    @AppStorage("appearance") private var appearance = Appearance.light
    @State private var addingShelf = false
    @State private var newShelf = ""
    @FocusState private var shelfFieldFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("folio")
                    .font(Theme.serif(26, .regular))
                    .foregroundStyle(Theme.ink)
                Spacer()
                Menu {
                    Button("Import Goodreads Library…") { library.importGoodreads() }
                    Button("Export Library as CSV…") { library.exportCSV() }
                    Divider()
                    Picker("Appearance", selection: $appearance) {
                        ForEach(Appearance.allCases) { Text($0.title).tag($0) }
                    }
                } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.muted)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
            }
            .padding(.horizontal, 20)
            .padding(.top, 46)

            Button { library.presentAddBook() } label: {
                Label("Add a Book", systemImage: "plus")
            }
            .buttonStyle(PrimaryButtonStyle())
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 14)

            ScrollView {
                VStack(alignment: .leading, spacing: 1) {
                    SidebarRow(title: "Home", icon: "house", selected: app.page == .home) { app.go(.home) }
                    SidebarRow(title: "Discover", icon: "safari", selected: app.page == .discover) { app.go(.discover) }
                    SidebarRow(title: "Reading Challenge", icon: "target", selected: app.page == .stats) { app.go(.stats) }

                    sectionTitle("Library")
                    ForEach([ReadingStatus.reading, .wantToRead, .read, .dnf]) { status in
                        row(status.title, status.symbol, .shelf(status), count: library.books(in: status).count)
                    }
                    row("Favourites", "heart", .favorites, count: library.books.filter(\.favorite).count)

                    sectionTitle("Shelves")
                    row("All Books", "books.vertical", .all, count: library.books.count)
                    ForEach(library.allTags, id: \.self) { tag in
                        row(tag.replacingOccurrences(of: "-", with: " ").capitalized, "tag", .tag(tag),
                            count: library.books.filter { $0.tags.contains(tag) }.count)
                            .contextMenu {
                                Button("Delete Shelf", role: .destructive) {
                                    if app.scope == .tag(tag) { app.scope = .all }
                                    library.deleteShelf(tag)
                                }
                            }
                    }
                    if addingShelf {
                        HStack(spacing: 10) {
                            Image(systemName: "tag").font(.system(size: 12)).foregroundStyle(Theme.muted).frame(width: 18)
                            TextField("Shelf name", text: $newShelf)
                                .textFieldStyle(.plain)
                                .font(.system(size: 13))
                                .focused($shelfFieldFocused)
                                .onSubmit {
                                    library.createShelf(newShelf)
                                    let slug = Library.shelfSlug(newShelf)
                                    newShelf = ""; addingShelf = false
                                    if !slug.isEmpty { app.show(.tag(slug)) }
                                }
                                .onExitCommand { newShelf = ""; addingShelf = false }
                        }
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(Theme.card, in: RoundedRectangle(cornerRadius: 6))
                        .onAppear { shelfFieldFocused = true }
                    } else {
                        SidebarRow(title: "Add a Shelf", icon: "plus", selected: false, muted: true) { addingShelf = true }
                    }
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 20)
            }
            .scrollIndicators(.never)
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Theme.sidebar)
    }

    private func row(_ title: String, _ icon: String, _ scope: Scope, count: Int) -> SidebarRow {
        SidebarRow(title: title, icon: icon, count: count, selected: app.page == .books && app.scope == scope) {
            app.show(scope)
        }
    }

    private func sectionTitle(_ t: String) -> some View {
        Text(t)
            .font(.system(size: 11.5, weight: .semibold))
            .foregroundStyle(Theme.ink.opacity(0.75))
            .padding(.horizontal, 10)
            .padding(.top, 18)
            .padding(.bottom, 6)
    }
}

struct SidebarRow: View {
    let title: String
    let icon: String
    var count: Int?
    let selected: Bool
    var muted = false
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 12.5))
                    .frame(width: 18)
                    .foregroundStyle(selected ? Theme.ink : Theme.muted)
                Text(title)
                    .font(.system(size: 13, weight: selected ? .medium : .regular))
                    .foregroundStyle(muted ? Theme.muted : Theme.ink)
                    .lineLimit(1)
                Spacer(minLength: 4)
                if let count, count > 0 {
                    Text("\(count)")
                        .font(.system(size: 11).monospacedDigit())
                        .foregroundStyle(Theme.muted)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6.5)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(selected ? Theme.accentSoft : hovering ? Theme.accentSoft.opacity(0.45) : .clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}
