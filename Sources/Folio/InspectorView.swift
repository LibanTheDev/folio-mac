import SwiftUI

struct InspectorView: View {
    @EnvironmentObject var library: Library
    let id: UUID

    var body: some View {
        Group {
            if let binding = library.binding(id) {
                InspectorContent(book: binding)
                    .id(id)
                    .task(id: id) {
                        if let b = library.book(id), b.synopsis == nil || b.coverID == nil {
                            await library.enrich(id)
                        }
                    }
            }
        }
    }
}

private struct InspectorContent: View {
    @EnvironmentObject var library: Library
    @EnvironmentObject var app: AppState
    @Binding var book: Book

    @AppStorage("inspector.open") private var openSections = "overview,notes,author"
    @State private var pageInput = ""
    @State private var tagInput = ""
    @State private var noteText = ""
    @State private var notePage = ""
    @State private var noteIsQuote = true
    @State private var confirmDelete = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button { app.toggleInspector() } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "chevron.right").font(.system(size: 9, weight: .bold))
                        Text("Hide")
                    }
                    .font(.system(size: 12))
                    .foregroundStyle(DS.textSecondary)
                }
                .buttonStyle(.plain)
                Spacer()
                Menu {
                    if let key = book.olWorkKey, let url = URL(string: "https://openlibrary.org\(key)") {
                        Link("View on Open Library", destination: url)
                    }
                    if book.status == .read {
                        Button("Start a Re-read") { library.startReread(book.id) }
                    }
                    Divider()
                    Button("Remove from Library…", role: .destructive) { confirmDelete = true }
                } label: {
                    Image(systemName: "ellipsis").foregroundStyle(DS.textSecondary)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
            }
            .padding(.horizontal, 18)
            .frame(height: 52)
            Rectangle().fill(DS.stroke).frame(height: 1)

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    hero
                    properties
                    if book.status == .reading { progress }
                    section("overview", "Overview") { overview }
                    section("notes", "Notes & Quotes", count: book.notes.count) { notes }
                    section("review", "My Review") { review }
                    section("shelves", "Shelves", count: book.tags.count) { shelves }
                    if let author = book.authors.first {
                        section("author", "Books by \(author)") {
                            AuthorBooks(author: author, excluding: book)
                        }
                    }
                }
                .padding(.bottom, 30)
            }
            .scrollIndicators(.never)
        }
        .confirmationDialog("Remove “\(book.title)” from your library?", isPresented: $confirmDelete) {
            Button("Remove", role: .destructive) {
                let id = book.id
                app.selectedBook = nil
                library.delete([id])
            }
        }
    }

    // MARK: Hero

    private var hero: some View {
        VStack(alignment: .leading, spacing: 0) {
            CoverView(book: book, size: "L")
                .frame(width: 148)
                .padding(.top, 20)
            HStack(alignment: .top) {
                Text(book.title)
                    .font(DS.serif(21, .medium))
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                Button { book.favorite.toggle() } label: {
                    Image(systemName: book.favorite ? "heart.fill" : "heart")
                        .font(.system(size: 17))
                        .foregroundStyle(book.favorite ? DS.favorite : DS.textTertiary)
                }
                .buttonStyle(.plain)
                .padding(.top, 3)
            }
            .padding(.top, 18)
            Text(book.authorLine)
                .font(.system(size: 13))
                .foregroundStyle(DS.textSecondary)
                .padding(.top, 3)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 18)
    }

    // MARK: Properties

    private var properties: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("Properties").font(.system(size: 12, weight: .semibold))
                .padding(.bottom, 2)
            prop("Shelf") {
                Menu {
                    ForEach(ReadingStatus.allCases) { s in
                        Button { library.setStatus(book.id, s) } label: { Label(s.title, systemImage: s.symbol) }
                    }
                } label: {
                    StatusBadge(status: book.status)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
            }
            prop("Rating") {
                HStack(spacing: 6) {
                    StarRating(rating: $book.rating, size: 12)
                    if let r = book.rating {
                        Text(r.formatted(.number.precision(.fractionLength(1))))
                            .font(.system(size: 11).monospacedDigit())
                            .foregroundStyle(DS.textSecondary)
                    }
                }
            }
            prop("Started") { optionalDate($book.dateStarted) }
            prop("Completed") { optionalDate($book.dateFinished) }
            prop("Pages") {
                TextField("—", value: $book.pageCount, format: .number)
                    .textFieldStyle(.plain)
                    .frame(width: 70)
            }
            if let y = book.publishYear {
                prop("Published") { Text(String(y)) }
            }
            if book.readCount > 1 {
                prop("Times read") { Text("\(book.readCount)") }
            }
            prop("Added") { Text(book.dateAdded.numericString) }
        }
        .font(.system(size: 11.5))
        .padding(.horizontal, 20)
        .padding(.bottom, 18)
    }

    private func prop<C: View>(_ label: String, @ViewBuilder _ content: () -> C) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .foregroundStyle(DS.textSecondary)
                .frame(width: 78, alignment: .leading)
            content()
            Spacer(minLength: 0)
        }
        .frame(minHeight: 20)
    }

    private func optionalDate(_ date: Binding<Date?>) -> some View {
        HStack(spacing: 4) {
            if let d = date.wrappedValue {
                DatePicker("", selection: Binding(get: { d }, set: { date.wrappedValue = $0 }), displayedComponents: .date)
                    .labelsHidden()
                    .datePickerStyle(.field)
                    .controlSize(.small)
                    .fixedSize()
                Button { date.wrappedValue = nil } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.plain)
                    .foregroundStyle(DS.textTertiary)
            } else {
                Button("Set date") { date.wrappedValue = Date() }
                    .buttonStyle(.plain)
                    .foregroundStyle(DS.textTertiary)
            }
        }
    }

    // MARK: Progress

    private var progress: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text("Progress").font(.system(size: 12, weight: .semibold))
                Spacer()
                Text("\(Int(book.progress * 100))%")
                    .font(.system(size: 12, weight: .semibold).monospacedDigit())
            }
            ProgressBar(value: book.progress, height: 6)
            Text(progressLine)
                .font(.system(size: 11))
                .foregroundStyle(DS.textSecondary)
            HStack(spacing: 6) {
                TextField("Page", text: $pageInput)
                    .textFieldStyle(.roundedBorder)
                    .controlSize(.small)
                    .frame(width: 64)
                    .onSubmit(logPage)
                Button("Update", action: logPage)
                    .buttonStyle(GlassButtonStyle())
                    .disabled(Int(pageInput) == nil)
                Spacer()
                Button("Finished") { library.setStatus(book.id, .read) }
                    .buttonStyle(PrimaryButtonStyle())
                    .fixedSize()
            }
        }
        .padding(14)
        .glass(.card, cornerRadius: DS.Radius.card - 2)
        .padding(.horizontal, 20)
        .padding(.bottom, 18)
    }

    private var progressLine: String {
        guard let pages = book.pageCount else { return "Page \(book.currentPage) · add a page count above to track %" }
        var line = "Page \(book.currentPage) of \(pages)"
        if let start = book.dateStarted, book.currentPage > 0 {
            let pace = Double(book.currentPage) / max(1, Date().timeIntervalSince(start) / 86_400)
            if pace > 0 { line += " · ~\(Int((Double(pages - book.currentPage) / pace).rounded(.up))) days left" }
        }
        return line
    }

    private func logPage() {
        guard let p = Int(pageInput) else { return }
        library.logProgress(book.id, page: p)
        pageInput = ""
    }

    // MARK: Collapsible sections

    private func section<C: View>(_ key: String, _ title: String, count: Int = 0, @ViewBuilder _ content: () -> C) -> some View {
        let open = openSections.split(separator: ",").contains(Substring(key))
        return VStack(alignment: .leading, spacing: 0) {
            Rectangle().fill(DS.stroke).frame(height: 1)
            Button {
                var set = Set(openSections.split(separator: ",").map(String.init))
                if open { set.remove(key) } else { set.insert(key) }
                withAnimation(.snappy(duration: 0.2)) { openSections = set.sorted().joined(separator: ",") }
            } label: {
                HStack {
                    Text(title).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                    if count > 0 {
                        Text("\(count)").font(.system(size: 11)).foregroundStyle(DS.textSecondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(DS.textSecondary)
                        .rotationEffect(.degrees(open ? 0 : -90))
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 13)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if open {
                content()
                    .padding(.horizontal, 20)
                    .padding(.bottom, 16)
                    .transition(.opacity)
            }
        }
    }

    @ViewBuilder private var overview: some View {
        if let synopsis = book.synopsis, !synopsis.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text(synopsis)
                    .font(.system(size: 11.5))
                    .lineSpacing(2.5)
                    .foregroundStyle(DS.textPrimary.opacity(0.85))
                    .textSelection(.enabled)
                let chips = Book.cleanLabels(book.subjects).prefix(8)
                if !chips.isEmpty {
                    FlowLayout(spacing: 4) { ForEach(Array(chips), id: \.self) { Chip(text: $0) } }
                }
            }
        } else if book.synopsis == nil {
            ProgressView().controlSize(.small)
        } else {
            Text("No description available.").font(.system(size: 11.5)).foregroundStyle(DS.textSecondary)
        }
    }

    private var notes: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(book.notes.sorted { ($0.page ?? 0, $0.created) < ($1.page ?? 0, $1.created) }) { note in
                HStack(alignment: .top, spacing: 10) {
                    Rectangle()
                        .fill(note.isQuote ? DS.accent : DS.textTertiary)
                        .frame(width: 2)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(note.isQuote ? "“\(note.text)”" : note.text)
                            .font(note.isQuote ? DS.serif(12.5).italic() : .system(size: 11.5))
                            .textSelection(.enabled)
                        Text([note.page.map { "p. \($0)" }, note.created.shortString].compactMap { $0 }.joined(separator: " · "))
                            .font(.system(size: 10))
                            .foregroundStyle(DS.textSecondary)
                    }
                    Spacer(minLength: 0)
                    Button { book.notes.removeAll { $0.id == note.id } } label: {
                        Image(systemName: "xmark").font(.system(size: 8, weight: .bold))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(DS.textTertiary)
                }
                .fixedSize(horizontal: false, vertical: true)
            }
            VStack(spacing: 6) {
                TextField(noteIsQuote ? "Save a quote…" : "Jot a thought…", text: $noteText, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11.5))
                    .lineLimit(1...5)
                    .padding(8)
                    .glass(.control, cornerRadius: DS.Radius.small + 1)
                HStack(spacing: 6) {
                    Picker("", selection: $noteIsQuote) {
                        Text("Quote").tag(true)
                        Text("Note").tag(false)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .controlSize(.small)
                    .frame(width: 110)
                    TextField("p.", text: $notePage)
                        .textFieldStyle(.roundedBorder)
                        .controlSize(.small)
                        .frame(width: 44)
                    Spacer()
                    Button("Add", action: addNote)
                        .buttonStyle(GlassButtonStyle())
                        .disabled(noteText.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private func addNote() {
        let text = noteText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        book.notes.append(BookNote(text: text, page: Int(notePage), isQuote: noteIsQuote))
        noteText = ""
        notePage = ""
    }

    private var review: some View {
        TextEditor(text: $book.review)
            .font(.system(size: 12))
            .scrollContentBackground(.hidden)
            .padding(6)
            .frame(minHeight: 110)
            .glass(.control, cornerRadius: DS.Radius.small + 1)
            .overlay(alignment: .topLeading) {
                if book.review.isEmpty {
                    Text("What did you think? Private to this Mac.")
                        .font(.system(size: 12))
                        .foregroundStyle(DS.textTertiary)
                        .padding(.horizontal, 11).padding(.vertical, 6)
                        .allowsHitTesting(false)
                }
            }
    }

    private var shelves: some View {
        FlowLayout(spacing: 5) {
            ForEach(book.tags, id: \.self) { tag in
                HStack(spacing: 4) {
                    Text(tag.replacingOccurrences(of: "-", with: " ").capitalized)
                    Button { book.tags.removeAll { $0 == tag } } label: {
                        Image(systemName: "xmark").font(.system(size: 7, weight: .bold))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(DS.textSecondary)
                }
                .font(.system(size: 11))
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(DS.fill, in: RoundedRectangle(cornerRadius: 5))
                .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(DS.stroke))
            }
            Menu {
                ForEach(library.allTags.filter { !book.tags.contains($0) }, id: \.self) { tag in
                    Button(tag.replacingOccurrences(of: "-", with: " ").capitalized) { book.tags.append(tag) }
                }
            } label: {
                Label("Add", systemImage: "plus").font(.system(size: 11))
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .disabled(library.allTags.allSatisfy { book.tags.contains($0) })
            TextField("New shelf", text: $tagInput)
                .textFieldStyle(.plain)
                .font(.system(size: 11))
                .frame(width: 80)
                .padding(.vertical, 4)
                .onSubmit {
                    let t = Library.shelfSlug(tagInput)
                    if !t.isEmpty, !book.tags.contains(t) { book.tags.append(t) }
                    tagInput = ""
                }
        }
    }
}

// MARK: - Books by author

private struct AuthorBooks: View {
    @EnvironmentObject var library: Library
    @EnvironmentObject var app: AppState
    let author: String
    let excluding: Book
    @State private var remote: [OLDoc] = []
    @State private var loaded = false
    @State private var selected: OLDoc?

    var body: some View {
        let own = library.books.filter { $0.id != excluding.id && $0.authors.first == author }
        let ownTitles = Set(library.books.map { $0.title.lowercased() })
        let others = remote.filter {
            $0.key != excluding.olWorkKey && library.contains(workKey: $0.key) == nil && !ownTitles.contains($0.title.lowercased()) && $0.cover_i != nil
        }
        ScrollView(.horizontal) {
            HStack(alignment: .top, spacing: 10) {
                ForEach(own) { b in
                    Button { app.open(b.id) } label: {
                        CoverView(book: b).frame(width: 62)
                            .overlay(alignment: .bottomTrailing) {
                                Image(systemName: b.status.symbol)
                                    .font(.system(size: 8, weight: .bold))
                                    .foregroundStyle(DS.onAccent)
                                    .padding(4)
                                    .background(DS.accent, in: Circle())
                                    .padding(3)
                            }
                    }
                    .buttonStyle(.plain)
                    .help(b.title)
                }
                ForEach(others.prefix(10)) { doc in
                    Button { selected = doc } label: {
                        CoverView(title: doc.title, author: doc.authorLine, url: doc.coverURL).frame(width: 62)
                    }
                    .buttonStyle(.plain)
                    .help(doc.title)
                }
                if !loaded && own.isEmpty {
                    ProgressView().controlSize(.small).frame(height: 93)
                } else if loaded && own.isEmpty && others.isEmpty {
                    Text("Nothing else found.").font(.system(size: 11)).foregroundStyle(DS.textSecondary)
                }
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 2)
        }
        .scrollIndicators(.never)
        .task(id: author) {
            remote = (try? await OpenLibrary.search("author:\"\(author)\"", limit: 16)) ?? []
            loaded = true
        }
        .sheet(item: $selected) { doc in
            RemoteBookSheet(doc: doc).environmentObject(library)
        }
    }
}
