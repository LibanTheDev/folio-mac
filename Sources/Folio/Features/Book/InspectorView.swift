import SwiftUI

/// Quick-look panel for the selected book.
struct InspectorView: View {
    @EnvironmentObject var library: Library
    let id: UUID

    var body: some View {
        if let binding = library.binding(id) {
            InspectorContent(book: binding)
                .id(id)
                .task(id: id) {
                    if let b = library.book(id), b.synopsis == nil || b.coverID == nil { await library.enrich(id) }
                }
        }
    }
}

private struct InspectorContent: View {
    @EnvironmentObject var library: Library
    @EnvironmentObject var app: AppState
    @Binding var book: Book
    @AppStorage("inspector.open") private var openSections = "overview,notes,related"

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button { app.toggleInspector() } label: {
                    Label("Hide", systemImage: "chevron.right").font(DS.Text.callout)
                }
                .buttonStyle(GhostButtonStyle())
                Spacer()
                Button { app.openDetail(book.id) } label: {
                    Label("Open", systemImage: "arrow.up.left.and.arrow.down.right")
                }
                .buttonStyle(GlassButtonStyle())
                .help("Open the full book page")
            }
            .padding(.horizontal, 12)
            .frame(height: 50)

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    hero
                    properties
                    if book.status == .reading {
                        ProgressPanel(book: book).padding(.horizontal, 16).padding(.bottom, 16)
                    }
                    section("overview", "Overview") { overview }
                    section("notes", "Notes & Highlights", count: book.notes.count) { NotesSection(book: $book, compact: true) }
                    section("shelves", "Tags & Collections") { TagsEditor(book: $book) }
                    section("related", "Related Books") { RelatedBooksRow(book: book) }
                }
                .padding(.bottom, 24)
            }
            .scrollIndicators(.never)
        }
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 0) {
            CoverView(book: book, size: "L", cornerRadius: 4)
                .frame(width: 140)
                .shadow(color: .black.opacity(0.22), radius: 14, y: 8)
                .padding(.top, 8)
                .onTapGesture(count: 2) { app.openDetail(book.id) }
            HStack(alignment: .top) {
                Text(book.title)
                    .font(DS.Text.title)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                FavoriteButton(book: book, size: 16).padding(.top, 3)
            }
            .padding(.top, 16)
            Text(book.authorLine)
                .font(DS.Text.body)
                .foregroundStyle(DS.textSecondary)
                .padding(.top, 3)
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 16)
    }

    private var properties: some View {
        VStack(alignment: .leading, spacing: 9) {
            StatusPicker(book: book).padding(.bottom, 4)
            prop("Rating") { RatingControl(rating: $book.rating, size: 12) }
            prop("Started") { DateField(date: $book.dateStarted) }
            prop("Completed") { DateField(date: $book.dateFinished) }
            prop("Pages") {
                TextField("—", value: $book.pageCount, format: .number).textFieldStyle(.plain).frame(width: 70)
            }
            if let y = book.publishYear { prop("Published") { Text(String(y)) } }
            if book.readCount > 1 { prop("Times read") { Text("\(book.readCount)") } }
        }
        .font(DS.Text.callout)
        .padding(.horizontal, 18)
        .padding(.bottom, 16)
    }

    private func prop<C: View>(_ label: String, @ViewBuilder _ content: () -> C) -> some View {
        HStack(spacing: 8) {
            Text(label).foregroundStyle(DS.textSecondary).frame(width: 76, alignment: .leading)
            content()
            Spacer(minLength: 0)
        }
        .frame(minHeight: 20)
    }

    private func section<C: View>(_ key: String, _ title: String, count: Int = 0, @ViewBuilder _ content: () -> C) -> some View {
        let open = openSections.split(separator: ",").contains(Substring(key))
        return VStack(alignment: .leading, spacing: 0) {
            Rectangle().fill(DS.stroke).frame(height: 1).padding(.horizontal, 12)
            Button {
                var set = Set(openSections.split(separator: ",").map(String.init))
                if open { set.remove(key) } else { set.insert(key) }
                Motion.perform { openSections = set.sorted().joined(separator: ",") }
            } label: {
                HStack {
                    Text(title).font(DS.Text.headline).lineLimit(1)
                    if count > 0 { Text("\(count)").font(DS.Text.caption).foregroundStyle(DS.textTertiary) }
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(DS.textTertiary)
                        .rotationEffect(.degrees(open ? 0 : -90))
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(.isHeader)
            .accessibilityValue(open ? "Expanded" : "Collapsed")
            if open {
                content()
                    .padding(.horizontal, 18)
                    .padding(.bottom, 14)
                    .transition(.opacity)
            }
        }
    }

    @ViewBuilder private var overview: some View {
        if let synopsis = book.synopsis, !synopsis.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text(synopsis)
                    .font(DS.Text.callout)
                    .lineSpacing(2.5)
                    .lineLimit(12)
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
            Text("No description available.").font(DS.Text.callout).foregroundStyle(DS.textTertiary)
        }
    }
}
