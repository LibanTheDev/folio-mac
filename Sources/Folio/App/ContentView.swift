import SwiftUI

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
        .overlay(alignment: .top) {
            if app.paletteShown {
                ZStack(alignment: .top) {
                    Color.black.opacity(0.12)
                        .ignoresSafeArea()
                        .onTapGesture { app.paletteShown = false }
                    CommandPalette()
                        .padding(.top, 90)
                        .transition(.opacity.combined(with: .scale(scale: 0.97, anchor: .top)))
                }
            }
        }
        .motion(Motion.gentle, value: app.paletteShown)
        .background(WindowConfigurator())
        .dropDestination(for: URL.self) { urls, _ in
            // Drop a Goodreads export anywhere on the window to import it.
            guard let csv = urls.first(where: { $0.pathExtension.lowercased() == "csv" }) else { return false }
            library.importGoodreads(from: csv)
            return true
        }
        .foregroundStyle(DS.textPrimary)
        .tint(DS.accent)
        .ignoresSafeArea(.container, edges: .top)
        .motion(Motion.standard, value: app.page)
        .motion(Motion.standard, value: app.detailBook)
        .environment(\.openBook) { app.open($0) }
        .environment(\.openDetail) { app.openDetail($0) }
        .sheet(item: $app.editingShelf) { shelf in
            ShelfEditor(draft: shelf)
                .environmentObject(library)
                .environmentObject(app)
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
        if let id = app.detailBook, library.book(id) != nil {
            BookDetailPage(id: id)
                .transition(.opacity.combined(with: .move(edge: .trailing)))
        } else {
            pageContent
        }
    }

    @ViewBuilder private var pageContent: some View {
        if !app.search.isEmpty, app.page == .home || app.page == .stats {
            SearchResultsView()
        } else {
            pageBody
        }
    }

    @ViewBuilder private var pageBody: some View {
        switch app.page {
        case .knowledge: KnowledgeView()
        case .ask: AskFolioView()
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
                    GlassSearchField(prompt: searchPrompt,
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
                if let session = library.activeSession {
                    SessionPill(session: session)
                }
                Button { app.paletteShown = true } label: { Image(systemName: "command") }
                    .buttonStyle(IconButtonStyle())
                    .help("Command palette (⌘K)")
                    .accessibilityLabel("Command palette")
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

    private var searchPrompt: String {
        switch app.page {
        case .discover: "Search Open Library"
        case .books: "Filter your books"
        case .knowledge: "Search your notes"
        default: "Search books and notes"
        }
    }

    private func openSearch() {
        searchOpen = true
        DispatchQueue.main.async { searchFocused = true }
    }
}

