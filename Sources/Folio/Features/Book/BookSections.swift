import SwiftUI

// MARK: - Status & rating

struct StatusPicker: View {
    @EnvironmentObject var library: Library
    let book: Book
    var body: some View {
        GlassSegmented(selection: Binding(get: { book.status }, set: { library.setStatus(book.id, $0) }),
                       options: ReadingStatus.allCases) { s in
            Text(s.shortTitle)
        }
    }
}

struct RatingControl: View {
    @Binding var rating: Double?
    var size: CGFloat = 16
    var body: some View {
        HStack(spacing: 8) {
            StarRating(rating: $rating, size: size)
            if let r = rating {
                Text(r.formatted(.number.precision(.fractionLength(1))))
                    .font(.system(size: size * 0.75, weight: .semibold).monospacedDigit())
                    .foregroundStyle(DS.textSecondary)
            } else {
                Text("Not rated").font(DS.Text.caption).foregroundStyle(DS.textTertiary)
            }
        }
    }
}

// MARK: - Progress

struct ProgressPanel: View {
    @EnvironmentObject var library: Library
    let book: Book
    @State private var pageInput = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Progress").font(DS.Text.headline)
                Spacer()
                Text("\(Int(book.progress * 100))%")
                    .font(.system(size: 13, weight: .semibold).monospacedDigit())
                    .contentTransition(.numericText())
            }
            ProgressBar(value: book.progress, tint: DS.statusReading, height: 6)
            Text(ReadingForecast.summary(for: book, sessions: library.sessions(for: book.id)))
                .font(DS.Text.caption)
                .foregroundStyle(DS.textSecondary)
            HStack(spacing: 6) {
                TextField("Page", text: $pageInput)
                    .textFieldStyle(GlassFieldStyle())
                    .frame(width: 70)
                    .onSubmit(logPage)
                Button("Update", action: logPage)
                    .buttonStyle(GlassButtonStyle())
                    .disabled(pageInput.intValue == nil)
                Spacer()
                Button("Mark Finished") { library.setStatus(book.id, .read) }
                    .buttonStyle(PrimaryButtonStyle(fullWidth: false))
            }
        }
        .padding(14)
        .glass(.card, cornerRadius: DS.Radius.card)
    }

    private func logPage() {
        guard let p = pageInput.intValue else { return }
        library.logProgress(book.id, page: p)
        pageInput = ""
    }
}

// MARK: - Notes

/// Notes, highlights and other knowledge for one book, grouped by kind, with a composer.
struct NotesSection: View {
    @EnvironmentObject var library: Library
    @Binding var book: Book
    var compact = false
    var only: Set<BookNote.Kind>?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            let notes = book.notes
                .filter { only?.contains($0.kind) ?? true }
                .sorted { ($0.page ?? Int.max, $0.created) < ($1.page ?? Int.max, $1.created) }
            if compact {
                ForEach(notes) { note in NoteRow(note: note, book: $book) }
            } else {
                let groups = BookNote.Kind.allCases.filter { k in notes.contains { $0.kind == k } }
                ForEach(groups) { kind in
                    VStack(alignment: .leading, spacing: 8) {
                        Label(kind.plural, systemImage: kind.symbol)
                            .font(DS.Text.eyebrow)
                            .textCase(.uppercase)
                            .foregroundStyle(DS.textTertiary)
                        ForEach(notes.filter { $0.kind == kind }) { note in NoteRow(note: note, book: $book) }
                    }
                }
            }
            let kinds = BookNote.Kind.allCases.filter { only?.contains($0) ?? true }
            NoteComposer(book: $book, defaultKind: kinds.first ?? .highlight, kinds: kinds)
        }
    }
}

struct NoteRow: View {
    let note: BookNote
    @Binding var book: Book
    @State private var editing = false
    @State private var draft = ""
    @State private var hovering = false

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            RoundedRectangle(cornerRadius: 1)
                .fill(note.kind.isFromBook ? DS.statusReading : DS.accent)
                .frame(width: 2.5)
            VStack(alignment: .leading, spacing: 4) {
                if editing {
                    TextEditor(text: $draft)
                        .font(.system(size: 12.5))
                        .scrollContentBackground(.hidden)
                        .frame(minHeight: 60)
                        .padding(4)
                        .glass(.control, cornerRadius: DS.Radius.small)
                    HStack {
                        Button("Cancel") { editing = false }.buttonStyle(GhostButtonStyle())
                        Button("Save") { save() }.buttonStyle(GlassButtonStyle())
                    }
                } else {
                    MarkdownText(text: note.text, serifItalic: note.kind.isFromBook)
                    HStack(spacing: 6) {
                        Label(note.kind.title, systemImage: note.kind.symbol)
                        if let loc = note.locationLabel { Text("·"); Text(loc) }
                        Text("·")
                        Text(note.created.shortString)
                        if !note.tags.isEmpty { Text("·"); Text(note.tags.map { "#\($0)" }.joined(separator: " ")) }
                        if !note.links.isEmpty { Text("·"); Label("\(note.links.count)", systemImage: "link") }
                    }
                    .font(DS.Text.micro)
                    .foregroundStyle(DS.textTertiary)
                    .labelStyle(.titleAndIcon)
                }
            }
            Spacer(minLength: 0)
            if !editing {
                Menu {
                    Button("Edit") { draft = note.text; editing = true }
                    Menu("Change Type") {
                        ForEach(BookNote.Kind.allCases) { k in
                            Button(k.title) { mutate { $0.kind = k } }
                        }
                    }
                    Divider()
                    Button("Delete", role: .destructive) { book.notes.removeAll { $0.id == note.id } }
                } label: {
                    Image(systemName: "ellipsis").font(.system(size: 11))
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .opacity(hovering ? 1 : 0.35)
                .accessibilityLabel("Note actions")
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .onHover { hovering = $0 }
    }

    private func mutate(_ change: (inout BookNote) -> Void) {
        guard let i = book.notes.firstIndex(where: { $0.id == note.id }) else { return }
        change(&book.notes[i])
        book.notes[i].updated = Date()
    }

    private func save() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        mutate { $0.text = text }
        editing = false
    }
}

struct NoteComposer: View {
    @Binding var book: Book
    var defaultKind: BookNote.Kind = .highlight
    var kinds: [BookNote.Kind] = BookNote.Kind.allCases
    @State private var text = ""
    @State private var page = ""
    @State private var chapter = ""
    @State private var kind: BookNote.Kind?

    var body: some View {
        let current = kind ?? defaultKind
        VStack(alignment: .leading, spacing: 6) {
            TextField(placeholder(current), text: $text, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 12.5))
                .lineLimit(1...6)
                .padding(9)
                .glass(.control, cornerRadius: DS.Radius.control)
            HStack(spacing: 6) {
                Menu {
                    ForEach(kinds) { k in
                        Button { kind = k } label: { Label(k.title, systemImage: k.symbol) }
                    }
                } label: {
                    Label(current.title, systemImage: current.symbol).font(DS.Text.caption)
                }
                .menuStyle(.button)
                .buttonStyle(GlassButtonStyle())
                .fixedSize()
                TextField("Chapter", text: $chapter).textFieldStyle(GlassFieldStyle()).frame(width: 90)
                TextField("Page", text: $page).textFieldStyle(GlassFieldStyle()).frame(width: 56)
                Spacer()
                Button("Add") { add(current) }
                    .buttonStyle(PrimaryButtonStyle(fullWidth: false))
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .keyboardShortcut(.return, modifiers: .command)
            }
        }
    }

    private func placeholder(_ k: BookNote.Kind) -> String {
        switch k {
        case .highlight, .quote: "Paste a passage from the book… (Markdown supported)"
        case .question: "What are you wondering about?"
        case .mentalModel: "Name the model and how it works…"
        default: "Write a thought… (Markdown supported)"
        }
    }

    private func add(_ k: BookNote.Kind) {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        book.notes.append(BookNote(kind: k, text: t, page: page.intValue, chapter: chapter.nilIfEmpty))
        text = ""
        page = ""
    }
}

/// Renders note Markdown: inline styles plus bullets, block quotes and headings.
struct MarkdownText: View {
    let text: String
    var serifItalic = false
    var lineLimit: Int?

    private enum Block: Hashable { case paragraph(String), bullet(String), quote(String), heading(String) }

    private var blocks: [Block] {
        text.components(separatedBy: "\n").compactMap { raw in
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { return nil }
            if line.hasPrefix("- ") || line.hasPrefix("* ") { return .bullet(String(line.dropFirst(2))) }
            if line.hasPrefix("> ") { return .quote(String(line.dropFirst(2))) }
            if line.hasPrefix("#") { return .heading(line.drop { $0 == "#" }.trimmingCharacters(in: .whitespaces)) }
            return .paragraph(line)
        }
    }

    private func inline(_ s: String) -> AttributedString {
        (try? AttributedString(markdown: s, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(s)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                switch block {
                case .paragraph(let s):
                    Text(inline(s)).font(serifItalic ? DS.serif(13.5).italic() : .system(size: 12.5))
                case .bullet(let s):
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("•").foregroundStyle(DS.textTertiary)
                        Text(inline(s)).font(.system(size: 12.5))
                    }
                case .quote(let s):
                    HStack(spacing: 8) {
                        RoundedRectangle(cornerRadius: 1).fill(DS.textTertiary.opacity(0.5)).frame(width: 2)
                        Text(inline(s)).font(DS.serif(13).italic()).foregroundStyle(DS.textSecondary)
                    }
                    .fixedSize(horizontal: false, vertical: true)
                case .heading(let s):
                    Text(inline(s)).font(.system(size: 13, weight: .semibold))
                }
            }
        }
        .lineSpacing(2.5)
        .lineLimit(lineLimit)
        .textSelection(.enabled)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Tags & collections

struct TagsEditor: View {
    @EnvironmentObject var library: Library
    @EnvironmentObject var app: AppState
    @Binding var book: Book
    @State private var tagInput = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            FlowLayout(spacing: 5) {
                ForEach(book.tags, id: \.self) { tag in
                    HStack(spacing: 4) {
                        Text("#\(tag)")
                        Button { book.tags.removeAll { $0 == tag } } label: {
                            Image(systemName: "xmark").font(.system(size: 7, weight: .bold))
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(DS.textTertiary)
                        .accessibilityLabel("Remove tag \(tag)")
                    }
                    .font(DS.Text.caption)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(Capsule().fill(DS.fill))
                    .overlay(Capsule().strokeBorder(DS.stroke))
                }
                TextField("Add tag", text: $tagInput)
                    .textFieldStyle(.plain)
                    .font(DS.Text.caption)
                    .frame(width: 80)
                    .padding(.vertical, 4)
                    .onSubmit {
                        let t = Library.tagSlug(tagInput)
                        if !t.isEmpty, !book.tags.contains(t) { book.tags.append(t) }
                        tagInput = ""
                    }
            }
            let collections = library.shelves.filter { $0.kind == .manual }
            if !collections.isEmpty {
                FlowLayout(spacing: 5) {
                    ForEach(collections) { s in
                        let member = s.bookIDs.contains(book.id)
                        Button {
                            if member { library.remove([book.id], fromShelf: s.id) } else { library.add([book.id], toShelf: s.id) }
                        } label: {
                            Label(s.name, systemImage: member ? "checkmark" : s.icon)
                                .font(DS.Text.caption)
                                .foregroundStyle(member ? DS.accent : DS.textSecondary)
                                .padding(.horizontal, 8).padding(.vertical, 4)
                                .background(Capsule().fill(member ? DS.selection : .clear))
                                .overlay(Capsule().strokeBorder(member ? DS.accent.opacity(0.3) : DS.stroke))
                        }
                        .buttonStyle(.plain)
                        .help(member ? "Remove from \(s.name)" : "Add to \(s.name)")
                    }
                }
            }
        }
    }
}

// MARK: - Reading history

struct ReadingHistoryList: View {
    @EnvironmentObject var library: Library
    let book: Book

    var body: some View {
        let throughs = book.allReadThroughs.reversed()
        let sessions = library.sessions(for: book.id)
        VStack(alignment: .leading, spacing: 8) {
            if throughs.isEmpty && sessions.isEmpty {
                Text("No reading history yet.").font(DS.Text.callout).foregroundStyle(DS.textTertiary)
            }
            ForEach(Array(throughs.enumerated()), id: \.element.id) { i, t in
                HStack(spacing: 8) {
                    Image(systemName: t.outcome == .abandoned ? "hand.raised" : (t.finished == nil ? "book" : "checkmark.circle"))
                        .foregroundStyle(t.outcome == .abandoned ? DS.statusDNF : t.finished == nil ? DS.statusReading : DS.statusRead)
                        .frame(width: 16)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(i == 0 && book.status == .reading ? "Current read" : t.outcome == .abandoned ? "Stopped reading" : "Read")
                            .font(DS.Text.callout.weight(.medium))
                        Text([t.started.map { "Started \($0.shortString)" }, t.finished.map { "finished \($0.shortString)" }]
                            .compactMap { $0 }.joined(separator: ", ").nilIfEmpty ?? "Dates unknown")
                            .font(DS.Text.caption).foregroundStyle(DS.textSecondary)
                    }
                    Spacer()
                    if let r = t.rating { StarRating(value: r, size: 9) }
                }
            }
            if book.readCount > book.allReadThroughs.filter({ $0.finished != nil }).count {
                Text("Read \(book.readCount)× in total (earlier dates weren't recorded).")
                    .font(DS.Text.caption).foregroundStyle(DS.textTertiary)
            }
            if !sessions.isEmpty {
                let total = sessions.reduce(0) { $0 + $1.duration }
                Text("\(sessions.count) session\(sessions.count == 1 ? "" : "s") · \(Self.duration(total)) logged")
                    .font(DS.Text.caption).foregroundStyle(DS.textSecondary)
                    .padding(.top, 4)
            }
        }
    }

    static func duration(_ t: TimeInterval) -> String {
        let f = DateComponentsFormatter()
        f.allowedUnits = t >= 3600 ? [.hour, .minute] : [.minute]
        f.unitsStyle = .abbreviated
        return f.string(from: max(60, t)) ?? ""
    }
}

// MARK: - Related books

struct RelatedBooksRow: View {
    @EnvironmentObject var library: Library
    @EnvironmentObject var app: AppState
    let book: Book
    var includeRemote = true
    @State private var remote: [OLDoc] = []
    @State private var loaded = false
    @State private var selected: OLDoc?

    var body: some View {
        let own = Related.books(for: book, in: library.books, shelves: library.shelves)
        let ownTitles = Set(library.books.map { $0.title.lowercased() })
        let others = remote.filter {
            $0.key != book.olWorkKey && library.contains(workKey: $0.key) == nil && !ownTitles.contains($0.title.lowercased()) && $0.cover_i != nil
        }
        VStack(alignment: .leading, spacing: 10) {
            if !own.isEmpty {
                Text("IN YOUR LIBRARY").font(DS.Text.eyebrow).tracking(0.6).foregroundStyle(DS.textTertiary)
                coverRow(own.map { b in AnyView(
                    Button { app.openDetail(b.id) } label: { CoverView(book: b).frame(width: 64) }
                        .buttonStyle(.plain).help("\(b.title) by \(b.authorLine)")
                ) })
            }
            if includeRemote, let author = book.authors.first {
                Text("MORE BY \(author.uppercased())").font(DS.Text.eyebrow).tracking(0.6).foregroundStyle(DS.textTertiary)
                if !loaded {
                    ProgressView().controlSize(.small)
                } else if others.isEmpty {
                    Text("Nothing else found on Open Library.").font(DS.Text.caption).foregroundStyle(DS.textTertiary)
                } else {
                    coverRow(others.prefix(12).map { doc in AnyView(
                        Button { selected = doc } label: {
                            CoverView(title: doc.title, author: doc.authorLine, url: doc.coverURL).frame(width: 64)
                        }
                        .buttonStyle(.plain).help(doc.title)
                    ) })
                }
            }
        }
        .task(id: book.authors.first) {
            guard includeRemote, let author = book.authors.first else { loaded = true; return }
            remote = (try? await OpenLibrary.search("author:\"\(author)\"", limit: 20)) ?? []
            loaded = true
        }
        .sheet(item: $selected) { doc in
            RemoteBookSheet(doc: doc).environmentObject(library)
        }
    }

    private func coverRow(_ items: [AnyView]) -> some View {
        ScrollView(.horizontal) {
            HStack(alignment: .top, spacing: 10) {
                ForEach(items.indices, id: \.self) { items[$0] }
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 2)
        }
        .scrollIndicators(.never)
    }
}
