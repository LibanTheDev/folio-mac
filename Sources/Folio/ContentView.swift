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
        Motion.perform {
            selectedBook = id
            inspectorShown = true
        }
    }

    func toggleInspector() {
        Motion.perform { inspectorShown.toggle() }
    }
}

struct ContentView: View {
    @EnvironmentObject var library: Library
    @EnvironmentObject var app: AppState

    var body: some View {
        ZStack {
            VisualEffectView(material: .underWindowBackground, blending: .behindWindow)
            AtmosphereBackground()
            HStack(spacing: 0) {
                SidebarView()
                    .frame(width: 236)
                    .glass(.panel, cornerRadius: DS.Radius.panel)
                    .padding(8)
                VStack(spacing: 0) {
                    TopBar()
                    page
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .id(app.page)
                        .transition(.opacity)
                }
                if app.inspectorShown, let id = app.selectedBook, library.book(id) != nil {
                    InspectorView(id: id)
                        .frame(width: 340)
                        .glass(.panel, cornerRadius: DS.Radius.panel)
                        .padding(8)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
        }
        .background(WindowConfigurator())
        .foregroundStyle(DS.textPrimary)
        .tint(DS.accent)
        .ignoresSafeArea(.container, edges: .top)
        .motion(Motion.standard, value: app.page)
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

/// Lets the user drag the window from empty titlebar space.
struct WindowDragArea: NSViewRepresentable {
    final class DragView: NSView {
        override func mouseDown(with event: NSEvent) { window?.performDrag(with: event) }
        override func mouseUp(with event: NSEvent) {
            if event.clickCount == 2 { window?.performZoom(nil) }
        }
    }
    func makeNSView(context: Context) -> NSView { DragView() }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

struct TopBar: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject var library: Library
    @State private var searchOpen = false
    @FocusState private var searchFocused: Bool

    var body: some View {
        ZStack {
            WindowDragArea()
            HStack(spacing: 2) {
                ForEach(Page.allCases) { page in
                    Button(page.rawValue) { app.go(page) }
                        .buttonStyle(PillButtonStyle(selected: app.page == page))
                }
            }
            .padding(3)
            .background(Capsule().fill(DS.fill))
            .overlay(Capsule().strokeBorder(DS.stroke))
            HStack(spacing: 6) {
                Spacer()
                if searchOpen || !app.search.isEmpty {
                    GlassSearchField(prompt: app.page == .discover ? "Search Open Library" : "Search your books",
                                     text: $app.search, focus: $searchFocused,
                                     onEscape: { app.search = ""; searchOpen = false })
                        .frame(width: 220)
                        .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .trailing)))
                } else {
                    Button { openSearch() } label: { Image(systemName: "magnifyingglass") }
                        .buttonStyle(IconButtonStyle())
                        .help("Search (⌘F)")
                        .accessibilityLabel("Search")
                }
                if app.selectedBook != nil {
                    Button { app.toggleInspector() } label: { Image(systemName: "sidebar.right") }
                        .buttonStyle(IconButtonStyle(selected: app.inspectorShown))
                        .help("Toggle inspector (⌥⌘I)")
                        .accessibilityLabel("Toggle inspector")
                }
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 54)
        .motion(Motion.gentle, value: searchOpen)
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
    @AppStorage("appearance") private var appearance = Appearance.system
    @State private var addingShelf = false
    @State private var newShelf = ""
    @FocusState private var shelfFieldFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 8) {
                Image(systemName: "book.pages")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(DS.onAccent)
                    .frame(width: 24, height: 24)
                    .background(RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(LinearGradient(colors: [DS.accentSecondary, DS.accent], startPoint: .top, endPoint: .bottom)))
                Text("Folio")
                    .font(DS.serif(19, .semibold))
                    .foregroundStyle(DS.textPrimary)
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
                        .foregroundStyle(DS.textSecondary)
                        .accessibilityLabel("Settings")
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
            }
            .padding(.horizontal, 16)
            .padding(.top, 44)

            Button { library.presentAddBook() } label: {
                Label("Add a Book", systemImage: "plus")
            }
            .buttonStyle(PrimaryButtonStyle())
            .padding(.horizontal, 12)
            .padding(.top, 14)
            .padding(.bottom, 8)

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
                            Image(systemName: "tag").font(.system(size: 12)).foregroundStyle(DS.textSecondary).frame(width: 18)
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
                        .padding(.horizontal, 9).padding(.vertical, 6)
                        .glass(.control, cornerRadius: DS.Radius.small + 1)
                        .onAppear { shelfFieldFocused = true }
                    } else {
                        SidebarRow(title: "Add a Shelf", icon: "plus", selected: false, muted: true) { addingShelf = true }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 16)
            }
            .scrollIndicators(.never)
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private func row(_ title: String, _ icon: String, _ scope: Scope, count: Int) -> SidebarRow {
        SidebarRow(title: title, icon: icon, count: count, selected: app.page == .books && app.scope == scope) {
            app.show(scope)
        }
    }

    private func sectionTitle(_ t: String) -> some View {
        SidebarSectionTitle(title: t)
    }
}
