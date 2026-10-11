import SwiftUI

/// The personal knowledge vault: every highlight, quote and thought across all books.
struct KnowledgeView: View {
    @EnvironmentObject var library: Library
    @EnvironmentObject var app: AppState
    @StateObject private var index = EmbeddingIndex.shared
    @State private var selected: UUID?
    @State private var kinds = Set<BookNote.Kind>()
    @State private var tag: String?
    @State private var bookFilter: UUID?
    @State private var semanticHits: [UUID: Double] = [:]

    private var notes: [NoteRef] {
        let q = app.search.trimmingCharacters(in: .whitespaces)
        let tokens = KeywordSearch.tokens(q)
        return library.allNotes.filter { ref in
            (kinds.isEmpty || kinds.contains(ref.note.kind))
                && (tag == nil || ref.note.tags.contains(tag!))
                && (bookFilter == nil || ref.book.id == bookFilter)
                && (tokens.isEmpty
                    || KeywordSearch.score(ref.note.plainText + " " + ref.note.tags.joined(separator: " ") + " " + ref.book.title,
                                           query: q, tokens: tokens) > 0
                    || semanticHits[ref.note.id] != nil)
        }
        .sorted { a, b in
            if !tokens.isEmpty { return (semanticHits[a.note.id] ?? 0) > (semanticHits[b.note.id] ?? 0) || a.note.updated > b.note.updated }
            return a.note.updated > b.note.updated
        }
    }

    var body: some View {
        let notes = notes
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                PageHeader(title: "Knowledge", caption: "\(library.allNotes.count) notes across \(library.books.filter { !$0.notes.isEmpty }.count) books")
                filters
                if notes.isEmpty {
                    EmptyStateView(icon: "brain.head.profile",
                                   title: library.allNotes.isEmpty ? "Your vault is empty" : "No matching notes",
                                   message: library.allNotes.isEmpty
                                       ? "Save highlights, quotes, lessons and mental models on any book. They'll collect here, searchable and connected."
                                       : "Try a different search or clear the filters.")
                } else {
                    ScrollView {
                        LazyVStack(spacing: 8) {
                            ForEach(notes) { ref in
                                NoteListRow(ref: ref, selected: selected == ref.note.id,
                                            meaning: semanticHits[ref.note.id] != nil && !app.search.isEmpty)
                                    .onTapGesture { selected = ref.note.id }
                            }
                        }
                        .padding(.bottom, 20)
                        .padding(.horizontal, 2)
                    }
                    .scrollIndicators(.never)
                }
            }
            .padding(.leading, DS.Space.page)
            .padding(.trailing, 16)
            .padding(.top, 10)
            .frame(width: 400)

            Group {
                if let id = selected, library.note(id) != nil {
                    NoteEditorPane(noteID: id)
                        .id(id)
                } else {
                    EmptyStateView(icon: "text.cursor", title: "Select a note",
                                   message: "Pick a note to read, edit and connect it to ideas from other books.")
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .glass(.card, cornerRadius: DS.Radius.panel)
            .padding(.trailing, 16)
            .padding(.bottom, 16)
            .padding(.top, 6)
        }
        .onAppear(perform: applyFocus)
        .onChange(of: app.focusedNote) { applyFocus() }
        .task(id: app.search) {
            let q = app.search.trimmingCharacters(in: .whitespaces)
            guard q.count >= 3 else { semanticHits = [:]; return }
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            semanticHits = Dictionary(uniqueKeysWithValues: index.semanticNotes(q, books: library.books).map { ($0.0.note.id, $0.1) })
        }
    }

    private func applyFocus() {
        if let f = app.focusedNote {
            selected = f
            kinds = []; tag = nil; bookFilter = nil
            app.focusedNote = nil
        } else if selected == nil {
            selected = library.allNotes.first?.note.id
        }
    }

    private var filters: some View {
        HStack(spacing: 6) {
            Menu {
                ForEach(BookNote.Kind.allCases) { k in
                    Toggle(isOn: Binding(get: { kinds.contains(k) }, set: { on in if on { kinds.insert(k) } else { kinds.remove(k) } })) {
                        Label(k.plural, systemImage: k.symbol)
                    }
                }
                if !kinds.isEmpty { Divider(); Button("All Types") { kinds = [] } }
            } label: {
                Label(kinds.isEmpty ? "All types" : kinds.count == 1 ? kinds.first!.plural : "\(kinds.count) types",
                      systemImage: "line.3.horizontal.decrease")
            }
            .menuStyle(.button).buttonStyle(GlassButtonStyle()).menuIndicator(.hidden).fixedSize()

            Menu {
                Button("All books") { bookFilter = nil }
                Divider()
                ForEach(library.books.filter { !$0.notes.isEmpty }.sorted { $0.title < $1.title }) { b in
                    Button("\(b.title) (\(b.notes.count))") { bookFilter = b.id }
                }
            } label: {
                Label(bookFilter.flatMap { library.book($0)?.title } ?? "All books", systemImage: "book.closed")
                    .lineLimit(1)
            }
            .menuStyle(.button).buttonStyle(GlassButtonStyle()).menuIndicator(.hidden).fixedSize()

            if !library.allNoteTags.isEmpty {
                Menu {
                    Button("All tags") { tag = nil }
                    Divider()
                    ForEach(library.allNoteTags, id: \.self) { t in Button("#\(t)") { tag = t } }
                } label: {
                    Label(tag.map { "#\($0)" } ?? "Tags", systemImage: "number")
                }
                .menuStyle(.button).buttonStyle(GlassButtonStyle()).menuIndicator(.hidden).fixedSize()
            }
            Spacer()
            NewNoteMenu { selected = $0 }
        }
    }
}

/// Creates a note on a chosen book.
struct NewNoteMenu: View {
    @EnvironmentObject var library: Library
    let onCreate: (UUID) -> Void

    var body: some View {
        Menu {
            let books = library.books.sorted { $0.updatedAt > $1.updatedAt }.prefix(15)
            ForEach(books) { b in
                Button(b.title) { if let id = library.addNote(to: b.id, kind: .reflection) { onCreate(id) } }
            }
        } label: {
            Label("New Note", systemImage: "square.and.pencil")
        }
        .menuStyle(.button)
        .buttonStyle(GlassButtonStyle())
        .menuIndicator(.hidden)
        .fixedSize()
        .disabled(library.books.isEmpty)
        .help("New note on a book")
    }
}

private struct NoteListRow: View {
    let ref: NoteRef
    let selected: Bool
    var meaning = false

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                Label(ref.note.kind.title, systemImage: ref.note.kind.symbol)
                    .font(DS.Text.eyebrow).textCase(.uppercase).tracking(0.4)
                    .foregroundStyle(ref.note.kind.isFromBook ? DS.statusReading : DS.accent)
                if meaning {
                    Text("similar meaning").font(DS.Text.micro).foregroundStyle(DS.textTertiary)
                }
                Spacer()
                if !ref.note.links.isEmpty { Image(systemName: "link").font(.system(size: 9)).foregroundStyle(DS.textTertiary) }
                Text(ref.note.updated.formatted(.relative(presentation: .named)))
                    .font(DS.Text.micro).foregroundStyle(DS.textTertiary)
            }
            Text(ref.note.plainText.isEmpty ? "Empty note" : ref.note.plainText)
                .font(ref.note.kind.isFromBook ? DS.serif(13).italic() : .system(size: 12.5))
                .foregroundStyle(ref.note.plainText.isEmpty ? DS.textTertiary : DS.textPrimary)
                .lineLimit(3)
                .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 6) {
                CoverView(book: ref.book, size: "S").frame(width: 12)
                Text(ref.book.title).font(DS.Text.caption.weight(.medium)).lineLimit(1)
                if let loc = ref.note.locationLabel { Text(loc).font(DS.Text.caption).foregroundStyle(DS.textTertiary) }
                if !ref.note.tags.isEmpty {
                    Text(ref.note.tags.map { "#\($0)" }.joined(separator: " ")).font(DS.Text.caption).foregroundStyle(DS.accent).lineLimit(1)
                }
            }
        }
        .padding(12)
        .hoverGlass(cornerRadius: DS.Radius.card - 2, selected: selected)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }
}

// MARK: - Editor

struct NoteEditorPane: View {
    @EnvironmentObject var library: Library
    @EnvironmentObject var app: AppState
    @StateObject private var index = EmbeddingIndex.shared
    @StateObject private var editor = MarkdownEditorController()
    let noteID: UUID
    @State private var preview = false
    @State private var tagInput = ""
    @State private var linking = false
    @State private var confirmDelete = false
    @State private var suggestions: [(NoteRef, Double)] = []

    private var note: Binding<BookNote>? {
        guard let ref = library.note(noteID) else { return nil }
        return Binding(get: { library.note(noteID)?.note ?? ref.note },
                       set: { new in library.updateNote(noteID) { $0 = new } })
    }

    var body: some View {
        if let note, let ref = library.note(noteID) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header(ref, note: note)
                    HStack(spacing: 8) {
                        TextField("Chapter", text: Binding(get: { note.wrappedValue.chapter ?? "" },
                                                           set: { note.wrappedValue.chapter = $0.isEmpty ? nil : $0 }))
                            .textFieldStyle(GlassFieldStyle()).frame(width: 180)
                        TextField("Page", text: Binding(get: { note.wrappedValue.page.map(String.init) ?? "" },
                                                        set: { note.wrappedValue.page = $0.intValue }))
                            .textFieldStyle(GlassFieldStyle()).frame(width: 70)
                        Spacer()
                        Text("Saved automatically").font(DS.Text.micro).foregroundStyle(DS.textTertiary)
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            MarkdownToolbar(controller: editor).disabled(preview)
                            Spacer()
                            GlassSegmented(selection: $preview, options: [false, true]) { Text($0 ? "Preview" : "Edit") }
                        }
                        Group {
                            if preview {
                                MarkdownText(text: note.wrappedValue.text, serifItalic: note.wrappedValue.kind.isFromBook)
                                    .padding(12)
                                    .frame(maxWidth: .infinity, minHeight: 180, alignment: .topLeading)
                            } else {
                                MarkdownEditor(text: note.text, controller: editor)
                                    .frame(minHeight: 220)
                            }
                        }
                        .glass(.control, cornerRadius: DS.Radius.control)
                    }
                    tags(note)
                    connections(ref)
                }
                .padding(20)
            }
            .scrollIndicators(.never)
            .task(id: note.wrappedValue.text) {
                try? await Task.sleep(for: .milliseconds(600))
                guard !Task.isCancelled, let r = library.note(noteID) else { return }
                suggestions = index.similarNotes(to: r.note, in: r.book, books: library.books)
            }
            .onAppear { if note.wrappedValue.text.isEmpty { DispatchQueue.main.async { editor.focus() } } }
            .confirmationDialog("Delete this note?", isPresented: $confirmDelete) {
                Button("Delete Note", role: .destructive) { library.deleteNote(noteID) }
            } message: {
                Text("Connections to it will be removed too.")
            }
        }
    }

    private func header(_ ref: NoteRef, note: Binding<BookNote>) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Button { app.openDetail(ref.book.id) } label: {
                HStack(spacing: 10) {
                    CoverView(book: ref.book, size: "S").frame(width: 28)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(ref.book.title).font(DS.Text.headline).lineLimit(1)
                        Text(ref.book.authorLine).font(DS.Text.caption).foregroundStyle(DS.textSecondary)
                    }
                }
            }
            .buttonStyle(.plain)
            .help("Open book")
            Spacer()
            Menu {
                ForEach(BookNote.Kind.allCases) { k in
                    Button { note.wrappedValue.kind = k } label: { Label(k.title, systemImage: k.symbol) }
                }
            } label: {
                Label(note.wrappedValue.kind.title, systemImage: note.wrappedValue.kind.symbol)
            }
            .menuStyle(.button).buttonStyle(GlassButtonStyle()).menuIndicator(.hidden).fixedSize()
            Button { confirmDelete = true } label: { Image(systemName: "trash") }
                .buttonStyle(IconButtonStyle())
                .help("Delete note")
                .accessibilityLabel("Delete note")
        }
    }

    private func tags(_ note: Binding<BookNote>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("TAGS").font(DS.Text.eyebrow).tracking(0.6).foregroundStyle(DS.textTertiary)
            FlowLayout(spacing: 5) {
                ForEach(note.wrappedValue.tags, id: \.self) { t in
                    HStack(spacing: 4) {
                        Text("#\(t)")
                        Button { note.wrappedValue.tags.removeAll { $0 == t } } label: {
                            Image(systemName: "xmark").font(.system(size: 7, weight: .bold))
                        }
                        .buttonStyle(.plain).foregroundStyle(DS.textTertiary)
                        .accessibilityLabel("Remove tag \(t)")
                    }
                    .font(DS.Text.caption)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(Capsule().fill(DS.selection))
                    .foregroundStyle(DS.accent)
                }
                TextField("Add tag (e.g. incentives)", text: $tagInput)
                    .textFieldStyle(.plain).font(DS.Text.caption).frame(width: 160).padding(.vertical, 4)
                    .onSubmit {
                        let t = Library.tagSlug(tagInput)
                        if !t.isEmpty, !note.wrappedValue.tags.contains(t) { note.wrappedValue.tags.append(t) }
                        tagInput = ""
                    }
            }
        }
    }

    private func connections(_ ref: NoteRef) -> some View {
        let linked = library.connections(of: noteID)
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("CONNECTIONS").font(DS.Text.eyebrow).tracking(0.6).foregroundStyle(DS.textTertiary)
                Spacer()
                Button { linking = true } label: { Label("Connect a Note", systemImage: "link.badge.plus") }
                    .buttonStyle(GhostButtonStyle())
                    .popover(isPresented: $linking, arrowEdge: .bottom) {
                        NoteLinkPicker(excluding: noteID) { target in
                            library.link(noteID, to: target)
                            linking = false
                        }
                        .environmentObject(library)
                    }
            }
            if linked.isEmpty {
                Text("Link this idea to related notes in other books to build your map of what you've learned.")
                    .font(DS.Text.caption).foregroundStyle(DS.textTertiary)
            }
            ForEach(linked) { other in
                ConnectionRow(ref: other, trailing: {
                    Button { library.unlink(noteID, other.note.id) } label: { Image(systemName: "link.badge.minus") }
                        .buttonStyle(IconButtonStyle(size: 24)).help("Remove connection")
                        .accessibilityLabel("Remove connection")
                }) { app.openNote(other.note.id) }
            }
            if !suggestions.isEmpty {
                Text("SUGGESTED · SIMILAR IDEAS IN OTHER BOOKS").font(DS.Text.eyebrow).tracking(0.6).foregroundStyle(DS.textTertiary)
                    .padding(.top, 6)
                ForEach(suggestions, id: \.0.id) { pair in
                    ConnectionRow(ref: pair.0, trailing: {
                        Button("Connect") {
                            library.link(noteID, to: pair.0.note.id)
                            suggestions.removeAll { $0.0.id == pair.0.id }
                        }
                        .buttonStyle(GlassButtonStyle())
                    }) { app.openNote(pair.0.note.id) }
                }
                Text("Suggestions are computed on this Mac from the meaning of your notes. Nothing is uploaded.")
                    .font(DS.Text.micro).foregroundStyle(DS.textTertiary)
            }
        }
    }
}

private struct ConnectionRow<Trailing: View>: View {
    let ref: NoteRef
    @ViewBuilder var trailing: () -> Trailing
    let onOpen: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: ref.note.kind.symbol).font(.system(size: 11)).foregroundStyle(DS.textTertiary).frame(width: 16)
            Button(action: onOpen) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(ref.note.plainText).font(.system(size: 12)).lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
                    Text(ref.book.title + (ref.note.locationLabel.map { " · \($0)" } ?? ""))
                        .font(DS.Text.micro).foregroundStyle(DS.textTertiary)
                }
            }
            .buttonStyle(.plain)
            trailing()
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: DS.Radius.control).fill(DS.fill))
    }
}

/// Search-and-pick list for connecting notes.
private struct NoteLinkPicker: View {
    @EnvironmentObject var library: Library
    let excluding: UUID
    let onPick: (UUID) -> Void
    @State private var query = ""
    @FocusState private var focused: Bool

    var body: some View {
        let tokens = KeywordSearch.tokens(query)
        let existing = Set(library.connections(of: excluding).map(\.note.id))
        let candidates = library.allNotes.filter { ref in
            ref.note.id != excluding && !existing.contains(ref.note.id)
                && (tokens.isEmpty || KeywordSearch.score(ref.note.plainText + " " + ref.book.title, query: query, tokens: tokens) > 0)
        }
        VStack(alignment: .leading, spacing: 10) {
            GlassSearchField(prompt: "Find a note to connect", text: $query, focus: $focused)
            ScrollView {
                VStack(spacing: 4) {
                    ForEach(candidates.prefix(30)) { ref in
                        Button { onPick(ref.note.id) } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(ref.note.plainText).font(.system(size: 12)).lineLimit(2)
                                Text(ref.book.title).font(DS.Text.micro).foregroundStyle(DS.textTertiary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(8)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    if candidates.isEmpty {
                        Text("No other notes match.").font(DS.Text.caption).foregroundStyle(DS.textTertiary).padding(8)
                    }
                }
            }
        }
        .padding(14)
        .frame(width: 360, height: 380)
        .onAppear { focused = true }
    }
}
