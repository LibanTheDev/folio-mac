import SwiftUI

/// Global results for the top search field: books and personal knowledge, keyword + meaning.
struct SearchResultsView: View {
    @EnvironmentObject var library: Library
    @EnvironmentObject var app: AppState
    @StateObject private var index = EmbeddingIndex.shared
    @State private var hits: [SearchHit] = []
    @State private var searching = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                PageHeader(title: "“\(app.search)”", caption: "Search · \(hits.count) result\(hits.count == 1 ? "" : "s")",
                           subtitle: index.isAvailable ? "Matches by keyword and by meaning (on-device, private)." : "Keyword matches.")
                if hits.isEmpty && !searching {
                    EmptyStateView(icon: "magnifyingglass", title: "No matches",
                                   message: "Nothing in your books, notes or highlights matches this search.")
                        .frame(height: 260)
                }
                let books = hits.filter { if case .book = $0.source { true } else { false } }
                let notes = hits.filter { if case .note = $0.source { true } else { false } }
                if !books.isEmpty {
                    SectionHeader(title: "Books", subtitle: "\(books.count)")
                    VStack(spacing: 8) { ForEach(books) { HitRow(hit: $0) } }
                }
                if !notes.isEmpty {
                    SectionHeader(title: "Notes & Highlights", subtitle: "\(notes.count)")
                    VStack(spacing: 8) { ForEach(notes) { HitRow(hit: $0) } }
                }
            }
            .padding(.horizontal, DS.Space.page)
            .padding(.top, 10)
            .padding(.bottom, 30)
        }
        .task(id: app.search) {
            searching = true
            try? await Task.sleep(for: .milliseconds(180))
            guard !Task.isCancelled else { return }
            hits = index.hybridSearch(app.search, books: library.books)
            searching = false
        }
    }
}

struct HitRow: View {
    @EnvironmentObject var library: Library
    @EnvironmentObject var app: AppState
    let hit: SearchHit

    var body: some View {
        Button(action: open) {
            HStack(alignment: .top, spacing: 12) {
                if let b = library.book(hit.bookID) { CoverView(book: b, size: "S").frame(width: 30) }
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        if let k = hit.noteKind {
                            Label(k.title, systemImage: k.symbol).font(DS.Text.eyebrow).textCase(.uppercase)
                                .foregroundStyle(k.isFromBook ? DS.statusReading : DS.accent)
                        }
                        Text(hit.title).font(DS.Text.callout.weight(.semibold)).lineLimit(1)
                        Spacer()
                        Text(hit.field == .meaning ? "Similar meaning" : "Matched \(hit.field.rawValue.lowercased())")
                            .font(DS.Text.micro).foregroundStyle(DS.textTertiary)
                    }
                    Text(hit.snippet).font(DS.Text.callout).foregroundStyle(DS.textSecondary).lineLimit(3)
                    if hit.noteKind != nil {
                        Text(hit.subtitle).font(DS.Text.micro).foregroundStyle(DS.textTertiary)
                    }
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .hoverGlass()
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens the source")
    }

    private func open() {
        switch hit.source {
        case .book(let id): app.search = ""; app.openDetail(id)
        case .note(let noteID, _): app.openNote(noteID)
        }
    }
}
