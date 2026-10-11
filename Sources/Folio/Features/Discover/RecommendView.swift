import SwiftUI

/// Conversational discovery: describe what you want; the model proposes, Open Library verifies.
struct RecommendView: View {
    @EnvironmentObject var library: Library
    @EnvironmentObject var app: AppState
    @StateObject private var ai = AISettings.shared
    @StateObject private var index = EmbeddingIndex.shared
    @State private var query = ""
    @State private var running = false
    @State private var result: DiscoveryResult?
    @State private var error: String?
    @State private var showUnverified = false
    @State private var fallbackDocs: [OLDoc] = []
    @State private var selected: OLDoc?

    private let examples = [
        "Biographies of people who built industrial conglomerates in emerging markets",
        "Books like The Outsiders but focused on European entrepreneurs",
        "The best books about capital allocation and private equity",
        "Overlooked books about businesspeople who built fortunes in obscure industries",
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                composer
                if running {
                    HStack(spacing: 10) {
                        ProgressView().controlSize(.small)
                        Text("Asking \(ai.provider == .anthropic ? "Claude" : "your model"), then checking every suggestion against Open Library…")
                            .font(DS.Text.callout).foregroundStyle(DS.textSecondary)
                    }
                    .padding(.top, 8)
                } else if let error {
                    GlassCard {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("Couldn't get recommendations", systemImage: "exclamationmark.triangle").font(DS.Text.headline)
                            Text(error).font(DS.Text.callout).foregroundStyle(DS.textSecondary)
                        }
                    }
                } else if let result {
                    results(result)
                } else if !fallbackDocs.isEmpty {
                    fallbackResults
                }
            }
            .padding(.horizontal, DS.Space.page)
            .padding(.top, 6)
            .padding(.bottom, 30)
        }
        .sheet(item: $selected) { doc in
            RemoteBookSheet(doc: doc).environmentObject(library)
        }
    }

    // MARK: Composer

    private var composer: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "sparkles")
                    .font(.system(size: 15))
                    .foregroundStyle(DS.accent)
                    .padding(.top, 2)
                TextField("Describe what you'd like to read next…", text: $query, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.system(size: 15))
                    .lineLimit(1...4)
                    .onSubmit(run)
                Button(action: run) {
                    Label(ai.enabled ? "Recommend" : "Search", systemImage: ai.enabled ? "arrow.up" : "magnifyingglass")
                }
                .buttonStyle(PrimaryButtonStyle(fullWidth: false))
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(query.trimmingCharacters(in: .whitespaces).isEmpty || running)
            }
            .padding(14)
            .glass(.card, cornerRadius: DS.Radius.panel)

            FlowLayout(spacing: 6) {
                ForEach(examples, id: \.self) { e in
                    Button(e) { query = e; run() }
                        .buttonStyle(GlassButtonStyle())
                        .disabled(running)
                }
            }
            if ai.enabled {
                Text(ai.dataDisclosure + " Suggestions are only shown if Open Library confirms the book exists.")
                    .font(DS.Text.caption).foregroundStyle(DS.textTertiary)
            } else {
                HStack(spacing: 8) {
                    Image(systemName: "info.circle").foregroundStyle(DS.textTertiary)
                    Text("AI recommendations are off, so this searches Open Library by keyword instead. Turn on AI in Settings to get personalised, explained picks.")
                        .font(DS.Text.caption).foregroundStyle(DS.textSecondary)
                    SettingsLink { Text("Open Settings") }
                        .buttonStyle(GhostButtonStyle())
                }
            }
        }
    }

    // MARK: Results

    @ViewBuilder
    private func results(_ r: DiscoveryResult) -> some View {
        SectionHeader(title: "Recommended for you", subtitle: "\(r.recommendations.count) verified · \(r.provider)")
        if r.recommendations.isEmpty {
            Text("None of the suggestions could be verified as new books for you. Try rephrasing or broadening the request.")
                .font(DS.Text.callout).foregroundStyle(DS.textSecondary)
        }
        VStack(spacing: 12) {
            ForEach(r.recommendations) { rec in
                RecommendationCard(rec: rec, onOpen: { selected = rec.doc }, onDismiss: {
                    library.dismissedRecommendations.append(rec.doc.key)
                    result?.recommendations.removeAll { $0.id == rec.id }
                })
            }
        }
        if !r.unverified.isEmpty || r.skippedKnown > 0 {
            VStack(alignment: .leading, spacing: 6) {
                if r.skippedKnown > 0 {
                    Text("\(r.skippedKnown) suggestion\(r.skippedKnown == 1 ? " was" : "s were") already in your library or previously dismissed.")
                }
                if !r.unverified.isEmpty {
                    Button(showUnverified ? "Hide unverified suggestions" : "\(r.unverified.count) suggestion\(r.unverified.count == 1 ? "" : "s") couldn't be verified on Open Library and \(r.unverified.count == 1 ? "was" : "were") hidden") {
                        showUnverified.toggle()
                    }
                    .buttonStyle(GhostButtonStyle())
                    .padding(.leading, -8)
                    if showUnverified {
                        Text("These may not exist or may be listed differently. Treat with caution:")
                        ForEach(r.unverified, id: \.self) { Text("· \($0)") }
                    }
                }
            }
            .font(DS.Text.caption)
            .foregroundStyle(DS.textTertiary)
        }
    }

    private var fallbackResults: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Open Library matches", subtitle: "keyword search · AI off")
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 138, maximum: 172), spacing: 24, alignment: .top)], spacing: 28) {
                ForEach(fallbackDocs) { doc in
                    VStack(alignment: .leading, spacing: 5) {
                        CoverView(title: doc.title, author: doc.authorLine, url: doc.coverURL)
                        Text(doc.title).font(.system(size: 12.5, weight: .semibold)).lineLimit(2)
                        Text(doc.authorLine).font(DS.Text.caption).foregroundStyle(DS.textSecondary).lineLimit(1)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { selected = doc }
                }
            }
        }
    }

    // MARK: Actions

    private func run() {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty, !running else { return }
        running = true
        error = nil
        result = nil
        fallbackDocs = []
        showUnverified = false
        Task {
            defer { running = false }
            guard ai.enabled else {
                do {
                    fallbackDocs = try await OpenLibrary.searchNaturalLanguage(q)
                    if fallbackDocs.isEmpty { self.error = "Open Library found nothing for that. Try fewer words, or turn on AI recommendations." }
                } catch { self.error = error.localizedDescription }
                return
            }
            do {
                let provider = try ai.makeProvider()
                let notes = ai.shareNotes ? index.semanticNotes(q, books: library.books, limit: 12).map(\.0) : []
                let dismissedTitles = library.dismissedRecommendations
                result = try await DiscoveryEngine.run(query: q, provider: provider, books: library.books,
                                                       interests: library.interests, dismissed: dismissedTitles,
                                                       shareLibrary: ai.shareLibrary, notes: notes)
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}

private struct RecommendationCard: View {
    @EnvironmentObject var library: Library
    @EnvironmentObject var app: AppState
    let rec: Recommendation
    let onOpen: () -> Void
    let onDismiss: () -> Void
    @State private var synopsis: String?
    @State private var added = false

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            CoverView(title: rec.doc.title, author: rec.doc.authorLine, url: rec.doc.coverURL)
                .frame(width: 92)
                .onTapGesture(perform: onOpen)
            VStack(alignment: .leading, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(rec.doc.title).font(DS.serif(18, .semibold))
                    Text([rec.doc.authorLine, rec.doc.first_publish_year.map(String.init)].compactMap { $0 }.joined(separator: " · "))
                        .font(DS.Text.callout).foregroundStyle(DS.textSecondary)
                }
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "sparkles").font(.system(size: 11)).foregroundStyle(DS.accent).padding(.top, 2)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(rec.reason).font(.system(size: 12.5))
                        Text("Why it fits · AI-generated").font(DS.Text.micro).foregroundStyle(DS.textTertiary)
                    }
                }
                .padding(10)
                .background(RoundedRectangle(cornerRadius: DS.Radius.control).fill(DS.selection.opacity(0.6)))
                if let synopsis, !synopsis.isEmpty {
                    Text(synopsis).font(DS.Text.callout).foregroundStyle(DS.textSecondary).lineLimit(3)
                    Text("Description · Open Library").font(DS.Text.micro).foregroundStyle(DS.textTertiary)
                }
                if !rec.relatedBookIDs.isEmpty {
                    HStack(spacing: 6) {
                        Text("Related in your library:").font(DS.Text.caption).foregroundStyle(DS.textTertiary)
                        ForEach(rec.relatedBookIDs.compactMap(library.book), id: \.id) { b in
                            Button(b.title) { app.openDetail(b.id) }
                                .buttonStyle(.plain)
                                .font(DS.Text.caption.weight(.medium))
                                .foregroundStyle(DS.accent)
                                .lineLimit(1)
                        }
                    }
                }
                HStack(spacing: 8) {
                    if added || library.contains(workKey: rec.doc.key) != nil {
                        Label("On Want to Read", systemImage: "checkmark").font(DS.Text.callout).foregroundStyle(DS.statusRead)
                    } else {
                        Button { library.add(Book(from: rec.doc), status: .wantToRead); added = true } label: {
                            Label("Want to Read", systemImage: "plus")
                        }
                        .buttonStyle(PrimaryButtonStyle(fullWidth: false))
                    }
                    Button("Details", action: onOpen).buttonStyle(GlassButtonStyle())
                    Button("Not for me", action: onDismiss)
                        .buttonStyle(GhostButtonStyle())
                        .help("Hide this and don't suggest it again")
                }
                .padding(.top, 2)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .hoverGlass()
        .task(id: rec.doc.key) { synopsis = await OpenLibrary.description(workKey: rec.doc.key) }
    }
}
