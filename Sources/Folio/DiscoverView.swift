import SwiftUI

struct DiscoverView: View {
    @EnvironmentObject var library: Library
    @EnvironmentObject var app: AppState
    @State private var results: [OLDoc] = []
    @State private var heading = "Trending This Week"
    @State private var activeGenre: String?
    @State private var loading = false
    @State private var error: String?
    @State private var selected: OLDoc?

    private let genres = ["Fantasy", "Science Fiction", "Mystery", "Romance", "Thriller", "Historical Fiction",
                          "Biography", "History", "Philosophy", "Psychology", "Business", "Poetry"]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                PageHeader(title: "Discover", caption: heading)
                FlowLayout(spacing: 6) {
                    Button("Trending") { activeGenre = nil; app.search = ""; Task { await loadTrending() } }
                        .buttonStyle(PillButtonStyle(selected: activeGenre == nil && app.search.isEmpty))
                    ForEach(genres, id: \.self) { g in
                        Button(g) {
                            activeGenre = g
                            app.search = ""
                            Task { await run("subject:\"\(g.lowercased())\"", heading: g) }
                        }
                        .buttonStyle(PillButtonStyle(selected: activeGenre == g))
                    }
                }

                if loading {
                    ProgressView().frame(maxWidth: .infinity, minHeight: 300)
                } else if let error {
                    ContentUnavailableView("Couldn't reach Open Library", systemImage: "wifi.exclamationmark", description: Text(error))
                } else if results.isEmpty {
                    ContentUnavailableView.search(text: app.search)
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 138, maximum: 172), spacing: 24, alignment: .top)], spacing: 28) {
                        ForEach(results) { doc in
                            ResultTile(doc: doc)
                                .onTapGesture { selected = doc }
                        }
                    }
                    .padding(.top, 8)
                }
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 22)
        }
        .task { if results.isEmpty { await loadTrending() } }
        .task(id: app.search) {
            // Search as you type, after a short pause.
            let q = app.search.trimmingCharacters(in: .whitespaces)
            if q.isEmpty {
                if activeGenre == nil, heading.hasPrefix("Results") { await loadTrending() }
                return
            }
            guard q.count >= 3 else { return }
            try? await Task.sleep(for: .milliseconds(450))
            guard !Task.isCancelled else { return }
            activeGenre = nil
            await run(q, heading: "Results for “\(q)”")
        }
        .sheet(item: $selected) { doc in
            RemoteBookSheet(doc: doc).environmentObject(library)
        }
    }

    private func loadTrending() async {
        loading = true; error = nil; heading = "Trending This Week"
        defer { loading = false }
        do { results = try await OpenLibrary.trending() } catch { self.error = error.localizedDescription }
    }

    private func run(_ q: String, heading: String) async {
        loading = true; error = nil; self.heading = heading
        defer { loading = false }
        do { results = try await OpenLibrary.search(q) } catch { self.error = error.localizedDescription }
    }
}

private struct ResultTile: View {
    @EnvironmentObject var library: Library
    let doc: OLDoc
    @State private var hovering = false

    var body: some View {
        let owned = library.contains(workKey: doc.key)
        VStack(alignment: .leading, spacing: 6) {
            CoverView(title: doc.title, author: doc.authorLine, url: doc.coverURL)
                .overlay(alignment: .bottomTrailing) {
                    if let owned {
                        StatusBadge(status: owned.status)
                            .background(.regularMaterial, in: Capsule())
                            .padding(6)
                    } else if hovering {
                        AddMenu(doc: doc).padding(6)
                    }
                }
                .offset(y: hovering ? -3 : 0)
                .animation(.spring(duration: 0.25), value: hovering)
            Text(doc.title).font(.system(size: 12.5, weight: .semibold)).lineLimit(2).padding(.top, 2)
            Text(doc.authorLine).font(.system(size: 11)).foregroundStyle(Theme.muted).lineLimit(1)
            if let y = doc.first_publish_year {
                Text(String(y)).font(.system(size: 10)).foregroundStyle(Theme.faint)
            }
        }
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
    }
}

private struct AddMenu: View {
    @EnvironmentObject var library: Library
    let doc: OLDoc

    var body: some View {
        Menu {
            ForEach(ReadingStatus.allCases) { s in
                Button { library.add(Book(from: doc), status: s) } label: { Label(s.title, systemImage: s.symbol) }
            }
        } label: {
            Image(systemName: "plus").fontWeight(.bold)
        } primaryAction: {
            library.add(Book(from: doc), status: .wantToRead)
        }
        .menuStyle(.button)
        .buttonStyle(.borderedProminent)
        .tint(Theme.accent)
        .controlSize(.small)
        .fixedSize()
        .help("Add to Want to Read (hold for more shelves)")
    }
}

struct RemoteBookSheet: View {
    @EnvironmentObject var library: Library
    @Environment(\.dismiss) private var dismiss
    let doc: OLDoc
    @State private var synopsis: String?
    @State private var loadingSynopsis = true

    var body: some View {
        let owned = library.contains(workKey: doc.key)
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                HStack(alignment: .top, spacing: 24) {
                    CoverView(title: doc.title, author: doc.authorLine,
                              urls: [doc.coverURL, doc.cover_i.flatMap { URL(string: "https://covers.openlibrary.org/b/id/\($0)-L.jpg") }].compactMap { $0 })
                        .frame(width: 160)
                    VStack(alignment: .leading, spacing: 10) {
                        Text(doc.title).font(Theme.serif(25, .medium))
                        Text(doc.authorLine).font(.system(size: 14)).foregroundStyle(Theme.muted)
                        HStack(spacing: 12) {
                            if let y = doc.first_publish_year { Text(String(y)) }
                            if let p = doc.number_of_pages_median { Text("\(p) pages") }
                            if let avg = doc.ratings_average, let n = doc.ratings_count, n > 0 {
                                Label("\(avg.formatted(.number.precision(.fractionLength(1)))) (\(n.formatted()))", systemImage: "star.fill")
                            }
                        }
                        .font(.callout).foregroundStyle(.secondary)
                        Divider().padding(.vertical, 4)
                        if loadingSynopsis {
                            ProgressView().controlSize(.small)
                        } else if let synopsis, !synopsis.isEmpty {
                            Text(synopsis).font(.system(size: 12.5)).lineSpacing(2.5).textSelection(.enabled).foregroundStyle(Theme.ink.opacity(0.85))
                        } else {
                            Text("No description available.").foregroundStyle(.tertiary)
                        }
                    }
                }
                .padding(28)
            }
            Divider()
            HStack {
                if let owned {
                    StatusBadge(status: owned.status)
                    Text("In your library").foregroundStyle(.secondary)
                }
                Spacer()
                Button("Close") { dismiss() }.keyboardShortcut(.cancelAction).buttonStyle(GhostButtonStyle())
                ForEach([ReadingStatus.read, .reading]) { s in
                    Button(s.title) { library.add(Book(from: doc), status: s); dismiss() }.buttonStyle(GhostButtonStyle())
                }
                Button("Want to Read") { library.add(Book(from: doc), status: .wantToRead); dismiss() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(PrimaryButtonStyle())
                    .fixedSize()
            }
            .padding(16)
            .background(Theme.sidebar)
        }
        .frame(width: 680, height: 460)
        .background(Theme.canvas)
        .task {
            synopsis = await OpenLibrary.description(workKey: doc.key)
            loadingSynopsis = false
        }
    }
}

struct AddBookSheet: View {
    @EnvironmentObject var library: Library
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var author = ""
    @State private var pages = ""
    @State private var isbn = ""
    @State private var status: ReadingStatus

    init(initialStatus: ReadingStatus = .wantToRead) {
        _status = State(initialValue: initialStatus)
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    TextField("Title", text: $title)
                    TextField("Author", text: $author)
                    TextField("Pages", text: $pages)
                    TextField("ISBN (optional, used for the cover)", text: $isbn)
                    Picker("Shelf", selection: $status) {
                        ForEach(ReadingStatus.allCases) { Text($0.title).tag($0) }
                    }
                } header: {
                    Text("Add a Book").font(Theme.serif(20, .medium)).foregroundStyle(Theme.ink)
                } footer: {
                    Text("Tip: Discover finds most books with covers and details filled in.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Add") {
                    var b = Book(title: title.trimmingCharacters(in: .whitespaces),
                                 authors: author.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) },
                                 isbn: isbn.filter { $0.isNumber || $0 == "X" }.nilIfEmpty,
                                 pageCount: Int(pages))
                    b.status = .wantToRead
                    let id = library.add(b, status: status)
                    dismiss()
                    Task { await library.enrich(id) }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding([.horizontal, .bottom], 20)
        }
        .frame(width: 440)
    }
}

extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
