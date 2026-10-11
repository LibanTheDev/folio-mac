import SwiftUI

/// Full-page view of a single book.
struct BookDetailPage: View {
    @EnvironmentObject var library: Library
    let id: UUID

    var body: some View {
        if let binding = library.binding(id) {
            BookDetailContent(book: binding)
                .id(id)
                .task(id: id) {
                    if let b = library.book(id), b.synopsis == nil || b.coverID == nil { await library.enrich(id) }
                }
        }
    }
}

private struct BookDetailContent: View {
    @EnvironmentObject var library: Library
    @EnvironmentObject var app: AppState
    @Binding var book: Book
    @State private var showFullSynopsis = false
    @State private var confirmDelete = false
    @State private var loggingSession = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                Button { app.closeDetail() } label: {
                    Label("Back", systemImage: "chevron.left")
                }
                .buttonStyle(GhostButtonStyle())
                .keyboardShortcut("[", modifiers: .command)
                .padding(.leading, -8)

                hero
                HStack(alignment: .top, spacing: 24) {
                    VStack(alignment: .leading, spacing: 28) {
                        if book.status == .reading { ProgressPanel(book: book) }
                        if let synopsis = book.synopsis, !synopsis.isEmpty { about(synopsis) }
                        section("Highlights & Notes", count: book.notes.filter { $0.kind != .mentalModel }.count) {
                            NotesSection(book: $book, only: Set(BookNote.Kind.allCases.filter { $0 != .mentalModel }))
                        }
                        section("Mental Models", count: book.notes.filter { $0.kind == .mentalModel }.count) {
                            NotesSection(book: $book, compact: true, only: [.mentalModel])
                        }
                        section("My Review") { review }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    VStack(alignment: .leading, spacing: 16) {
                        GlassCard(padding: 16) { details }
                        GlassCard(padding: 16) {
                            VStack(alignment: .leading, spacing: 10) {
                                HStack {
                                    Text("Reading History").font(DS.Text.headline)
                                    Spacer()
                                    Button { loggingSession = true } label: { Label("Log", systemImage: "plus") }
                                        .buttonStyle(GhostButtonStyle())
                                        .help("Log a past reading session")
                                }
                                ReadingHistoryList(book: book)
                                if !library.sessions(for: book.id).isEmpty {
                                    SessionList(bookID: book.id, limit: 6)
                                }
                            }
                        }
                        GlassCard(padding: 16) {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("Tags & Collections").font(DS.Text.headline)
                                TagsEditor(book: $book)
                            }
                        }
                    }
                    .frame(width: 300)
                }
                section("Related Books") { RelatedBooksRow(book: book) }
            }
            .padding(.horizontal, DS.Space.page)
            .padding(.vertical, 12)
            .frame(maxWidth: 1100, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .sheet(isPresented: $loggingSession) {
            LogSessionSheet(bookID: book.id).environmentObject(library)
        }
        .confirmationDialog("Remove “\(book.title)” from your library?", isPresented: $confirmDelete) {
            Button("Remove", role: .destructive) {
                let id = book.id
                app.closeDetail()
                app.selectedBook = nil
                library.delete([id])
            }
        } message: {
            Text("Its notes, highlights and reading sessions will be deleted too.")
        }
    }

    // MARK: Hero

    private var hero: some View {
        HStack(alignment: .bottom, spacing: 28) {
            CoverView(book: book, size: "L", cornerRadius: 5)
                .frame(width: 190)
                .shadow(color: .black.opacity(0.25), radius: 22, y: 14)
            VStack(alignment: .leading, spacing: 10) {
                if !book.genres.isEmpty {
                    Text(book.genres.prefix(3).joined(separator: " · ").uppercased())
                        .font(DS.Text.eyebrow).tracking(0.9).foregroundStyle(DS.textTertiary)
                }
                Text(book.title)
                    .font(DS.serif(34, .semibold))
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 6) {
                    ForEach(book.authors, id: \.self) { a in
                        Button(a) {
                            app.show(.all)
                            app.search = a
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 15))
                        .foregroundStyle(DS.accent)
                        .help("Show books by \(a)")
                    }
                }
                Text([book.publishYear.map(String.init), book.pageCount.map { "\($0) pages" }, book.publisher]
                    .compactMap { $0 }.joined(separator: " · "))
                    .font(DS.Text.callout).foregroundStyle(DS.textSecondary)

                HStack(spacing: 14) {
                    StatusPicker(book: book)
                    RatingControl(rating: $book.rating, size: 17)
                }
                .padding(.top, 6)

                HStack(spacing: 8) {
                    if library.activeSession?.bookID == book.id {
                        Label("Session in progress", systemImage: "timer")
                            .font(DS.Text.callout.weight(.medium))
                            .foregroundStyle(DS.accent)
                    } else if book.status != .read {
                        Button { library.startSession(book.id) } label: { Label("Start Reading Session", systemImage: "play.fill") }
                            .buttonStyle(PrimaryButtonStyle(fullWidth: false))
                    } else {
                        Button { library.startReread(book.id) } label: { Label("Start a Re-read", systemImage: "arrow.counterclockwise") }
                            .buttonStyle(GlassButtonStyle())
                    }
                    Button { book.favorite.toggle() } label: {
                        Label(book.favorite ? "Favourite" : "Add to Favourites", systemImage: book.favorite ? "heart.fill" : "heart")
                    }
                    .buttonStyle(GlassButtonStyle())
                    .foregroundStyle(book.favorite ? DS.favorite : DS.textPrimary)
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
                        Image(systemName: "ellipsis")
                    }
                    .menuStyle(.button)
                    .buttonStyle(GlassButtonStyle())
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .accessibilityLabel("More actions")
                }
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: Sections

    private func section<C: View>(_ title: String, count: Int = 0, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: title, subtitle: count > 0 ? "\(count)" : nil)
            content()
        }
    }

    private func about(_ synopsis: String) -> some View {
        section("About") {
            VStack(alignment: .leading, spacing: 8) {
                Text(synopsis)
                    .font(.system(size: 13))
                    .lineSpacing(3)
                    .foregroundStyle(DS.textPrimary.opacity(0.88))
                    .lineLimit(showFullSynopsis ? nil : 7)
                    .textSelection(.enabled)
                if synopsis.count > 500 {
                    Button(showFullSynopsis ? "Show less" : "Show more") { Motion.perform { showFullSynopsis.toggle() } }
                        .buttonStyle(GhostButtonStyle())
                        .padding(.leading, -8)
                }
                let chips = Book.cleanLabels(book.subjects).prefix(10)
                if !chips.isEmpty {
                    FlowLayout(spacing: 5) { ForEach(Array(chips), id: \.self) { Chip(text: $0) } }
                }
            }
        }
    }

    private var review: some View {
        TextEditor(text: $book.review)
            .font(.system(size: 13))
            .scrollContentBackground(.hidden)
            .padding(8)
            .frame(minHeight: 120)
            .glass(.control, cornerRadius: DS.Radius.control)
            .overlay(alignment: .topLeading) {
                if book.review.isEmpty {
                    Text("What did you think? Private to this Mac.")
                        .font(.system(size: 13))
                        .foregroundStyle(DS.textTertiary)
                        .padding(.horizontal, 13).padding(.vertical, 8)
                        .allowsHitTesting(false)
                }
            }
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("Details").font(DS.Text.headline).padding(.bottom, 2)
            row("Started") { DateField(date: $book.dateStarted) }
            row("Completed") { DateField(date: $book.dateFinished) }
            row("Pages") { TextField("—", value: $book.pageCount, format: .number).textFieldStyle(.plain) }
            row("Published") { TextField("—", value: $book.publishYear, format: .number.grouping(.never)).textFieldStyle(.plain) }
            row("Publisher") { TextField("—", text: optional($book.publisher)).textFieldStyle(.plain) }
            row("Edition") { TextField("—", text: optional($book.edition)).textFieldStyle(.plain) }
            row("Format") { TextField("e.g. Hardcover", text: optional($book.format)).textFieldStyle(.plain) }
            row("ISBN") { TextField("—", text: optional($book.isbn)).textFieldStyle(.plain).textSelection(.enabled) }
            row("Added") { Text(book.dateAdded.shortString) }
        }
        .font(DS.Text.callout)
    }

    private func row<C: View>(_ label: String, @ViewBuilder _ content: () -> C) -> some View {
        HStack(spacing: 8) {
            Text(label).foregroundStyle(DS.textSecondary).frame(width: 78, alignment: .leading)
            content()
            Spacer(minLength: 0)
        }
        .frame(minHeight: 20)
    }

    private func optional(_ b: Binding<String?>) -> Binding<String> {
        Binding(get: { b.wrappedValue ?? "" }, set: { b.wrappedValue = $0.isEmpty ? nil : $0 })
    }
}

/// Compact date editor that can be cleared.
struct DateField: View {
    @Binding var date: Date?
    var body: some View {
        HStack(spacing: 4) {
            if let d = date {
                DatePicker("", selection: Binding(get: { d }, set: { date = $0 }), displayedComponents: .date)
                    .labelsHidden()
                    .datePickerStyle(.field)
                    .controlSize(.small)
                    .fixedSize()
                Button { date = nil } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.plain)
                    .foregroundStyle(DS.textTertiary)
                    .accessibilityLabel("Clear date")
            } else {
                Button("Set date") { date = Date() }
                    .buttonStyle(.plain)
                    .foregroundStyle(DS.textTertiary)
            }
        }
    }
}
