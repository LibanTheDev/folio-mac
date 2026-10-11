import SwiftUI

struct SidebarView: View {
    @EnvironmentObject var library: Library
    @EnvironmentObject var app: AppState
    @AppStorage("appearance") private var appearance = Appearance.system
    @State private var addingTag = false
    @State private var newTag = ""
    @State private var renamingTag: String?
    @State private var renameText = ""
    @State private var deletingShelf: Shelf?
    @FocusState private var tagFieldFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Button { library.presentAddBook() } label: {
                Label("Add a Book", systemImage: "plus")
            }
            .buttonStyle(PrimaryButtonStyle())
            .padding(.horizontal, 12)
            .padding(.top, 14)
            .padding(.bottom, 8)
            .help("Add a book (⌘N)")

            ScrollView {
                VStack(alignment: .leading, spacing: 1) {
                    SidebarRow(title: "Home", icon: "house", selected: app.page == .home && app.detailBook == nil) { app.go(.home) }
                    SidebarRow(title: "Knowledge", icon: "brain.head.profile", count: library.allNotes.count,
                               selected: app.page == .knowledge && app.detailBook == nil) { app.go(.knowledge) }
                    SidebarRow(title: "Ask Folio", icon: "text.bubble", selected: app.page == .ask && app.detailBook == nil) { app.go(.ask) }
                    SidebarRow(title: "Discover", icon: "safari", selected: app.page == .discover && app.detailBook == nil) { app.go(.discover) }
                    SidebarRow(title: "Insights", icon: "chart.xyaxis.line", selected: app.page == .stats && app.detailBook == nil) { app.go(.stats) }

                    SidebarSectionTitle(title: "Library")
                    scopeRow("All Books", "books.vertical", .all, count: library.books.count)
                    ForEach([ReadingStatus.reading, .wantToRead, .read, .dnf]) { status in
                        scopeRow(status.title, status.symbol, .status(status), count: library.books(in: status).count)
                    }
                    scopeRow("Favourites", "heart", .favorites, count: library.books.filter(\.favorite).count)

                    shelvesSection
                    tagsSection
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 16)
            }
            .scrollIndicators(.never)
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .alert("Rename Tag", isPresented: Binding(get: { renamingTag != nil }, set: { if !$0 { renamingTag = nil } })) {
            TextField("Name", text: $renameText)
            Button("Rename") {
                if let t = renamingTag {
                    library.renameTag(t, to: renameText)
                    if app.scope == .tag(t) { app.scope = .tag(Library.tagSlug(renameText)) }
                }
                renamingTag = nil
            }
            Button("Cancel", role: .cancel) { renamingTag = nil }
        }
        .confirmationDialog("Delete “\(deletingShelf?.name ?? "")”?",
                            isPresented: Binding(get: { deletingShelf != nil }, set: { if !$0 { deletingShelf = nil } })) {
            Button("Delete Shelf", role: .destructive) {
                if let s = deletingShelf {
                    if app.scope == .shelf(s.id) { app.scope = .all }
                    library.deleteShelf(s.id)
                }
                deletingShelf = nil
            }
        } message: {
            Text("The books themselves stay in your library.")
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 8) {
            Image(systemName: "book.pages")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(DS.onAccent)
                .frame(width: 24, height: 24)
                .background(RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(LinearGradient(colors: [DS.accentSecondary, DS.accent], startPoint: .top, endPoint: .bottom)))
                .accessibilityHidden(true)
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
    }

    // MARK: Shelves

    private var shelvesSection: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack {
                SidebarSectionTitle(title: "Shelves")
                Spacer()
                Menu {
                    Button("New Collection…") { app.editingShelf = Shelf(name: "", icon: "books.vertical", kind: .manual) }
                    Button("New Smart Shelf…") {
                        app.editingShelf = Shelf(name: "", icon: "sparkles", kind: .smart,
                                                 rules: [ShelfRule(.rating, .atLeast, "4")])
                    }
                    Divider()
                    Menu("From Template") {
                        ForEach(Shelf.templates(year: library.currentYear), id: \.name) { t in
                            Button(t.name) {
                                var s = t
                                s.id = UUID()
                                library.addShelf(s)
                                app.show(.shelf(s.id))
                            }
                        }
                    }
                } label: {
                    Image(systemName: "plus").font(.system(size: 10, weight: .semibold))
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .foregroundStyle(DS.textTertiary)
                .padding(.top, 11)
                .padding(.trailing, 8)
                .help("New shelf")
                .accessibilityLabel("New shelf")
            }
            if library.shelves.isEmpty {
                Text("Group books into collections, or build smart shelves that fill themselves.")
                    .font(DS.Text.caption)
                    .foregroundStyle(DS.textTertiary)
                    .padding(.horizontal, 10)
                    .padding(.bottom, 4)
            }
            ForEach(library.shelves) { shelf in
                ShelfRow(shelf: shelf,
                         count: library.books(on: shelf).count,
                         selected: app.page == .books && app.detailBook == nil && app.scope == .shelf(shelf.id),
                         onSelect: { app.show(.shelf(shelf.id)) })
                    .contextMenu {
                        Button("Edit Shelf…") { app.editingShelf = shelf }
                        Button("Move Up") { library.moveShelf(shelf.id, by: -1) }
                            .disabled(library.shelves.first?.id == shelf.id)
                        Button("Move Down") { library.moveShelf(shelf.id, by: 1) }
                            .disabled(library.shelves.last?.id == shelf.id)
                        Divider()
                        Button("Delete Shelf…", role: .destructive) { deletingShelf = shelf }
                    }
            }
        }
    }

    // MARK: Tags

    private var tagsSection: some View {
        VStack(alignment: .leading, spacing: 1) {
            SidebarSectionTitle(title: "Tags")
            ForEach(library.allTags, id: \.self) { tag in
                scopeRow(tag.replacingOccurrences(of: "-", with: " ").capitalized, "number", .tag(tag),
                         count: library.books.filter { $0.tags.contains(tag) }.count)
                    .contextMenu {
                        Button("Rename Tag…") { renameText = tag; renamingTag = tag }
                        Button("Delete Tag", role: .destructive) {
                            if app.scope == .tag(tag) { app.scope = .all }
                            library.deleteTag(tag)
                        }
                    }
            }
            if addingTag {
                HStack(spacing: 9) {
                    Image(systemName: "number").font(.system(size: 12)).foregroundStyle(DS.textSecondary).frame(width: 18)
                    TextField("Tag name", text: $newTag)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                        .focused($tagFieldFocused)
                        .onSubmit {
                            library.createTag(newTag)
                            let slug = Library.tagSlug(newTag)
                            newTag = ""; addingTag = false
                            if !slug.isEmpty { app.show(.tag(slug)) }
                        }
                        .onExitCommand { newTag = ""; addingTag = false }
                }
                .padding(.horizontal, 9).padding(.vertical, 6)
                .glass(.control, cornerRadius: DS.Radius.small + 1)
                .onAppear { tagFieldFocused = true }
            } else {
                SidebarRow(title: "Add a Tag", icon: "plus", selected: false, muted: true) { addingTag = true }
            }
        }
    }

    private func scopeRow(_ title: String, _ icon: String, _ scope: Scope, count: Int) -> SidebarRow {
        SidebarRow(title: title, icon: icon, count: count,
                   selected: app.page == .books && app.detailBook == nil && app.scope == scope) {
            app.show(scope)
        }
    }
}

/// A shelf in the sidebar. Books can be dropped onto collections; shelves can be dragged to reorder.
private struct ShelfRow: View {
    @EnvironmentObject var library: Library
    let shelf: Shelf
    let count: Int
    let selected: Bool
    let onSelect: () -> Void
    @State private var targeted = false

    var body: some View {
        SidebarRow(title: shelf.name, icon: shelf.kind == .smart ? (shelf.icon == "books.vertical" ? "sparkles" : shelf.icon) : shelf.icon,
                   count: count, selected: selected, action: onSelect)
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.small + 1, style: .continuous)
                    .strokeBorder(targeted ? DS.accent : .clear, lineWidth: 1.5)
            )
            .draggable("shelf:\(shelf.id.uuidString)")
            .dropDestination(for: String.self) { items, _ in
                var handled = false
                for item in items {
                    if item.hasPrefix("shelf:"), let id = UUID(uuidString: String(item.dropFirst(6))) {
                        library.moveShelf(id, before: shelf.id)
                        handled = true
                    } else if shelf.kind == .manual, let id = UUID(uuidString: item) {
                        library.add([id], toShelf: shelf.id)
                        handled = true
                    }
                }
                return handled
            } isTargeted: { targeted = $0 }
            .help(shelf.kind == .smart ? "Smart shelf: updates automatically" : "Collection: drop books here to add them")
    }
}
