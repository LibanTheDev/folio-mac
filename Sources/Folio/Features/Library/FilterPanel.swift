import SwiftUI

/// Popover for combining library filters.
struct FilterPanel: View {
    @EnvironmentObject var library: Library
    @Binding var filter: LibraryFilter
    @State private var authorQuery = ""

    private var completedYears: [Int] {
        let cal = Calendar.current
        return Array(Set(library.books.compactMap { b in b.status == .read ? b.dateFinished.map { cal.component(.year, from: $0) } : nil })).sorted(by: >)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Filters").font(DS.Text.headline)
                Spacer()
                Button("Reset") { filter = LibraryFilter() }
                    .buttonStyle(GhostButtonStyle())
                    .disabled(filter.isEmpty)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            Divider().overlay(DS.stroke)
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    section("Status") {
                        FlowLayout(spacing: 5) {
                            ForEach(ReadingStatus.allCases) { s in
                                toggleChip(s.title, on: filter.statuses.contains(s)) { toggle(&filter.statuses, s) }
                            }
                            toggleChip("Favourites", on: filter.favoritesOnly) { filter.favoritesOnly.toggle() }
                        }
                    }
                    section("Rating") {
                        FlowLayout(spacing: 5) {
                            toggleChip("Any", on: filter.minRating == nil && !filter.unratedOnly) { filter.minRating = nil; filter.unratedOnly = false }
                            ForEach([3.0, 4.0, 4.5, 5.0], id: \.self) { r in
                                toggleChip("\(r.formatted())★+", on: filter.minRating == r) {
                                    filter.minRating = filter.minRating == r ? nil : r
                                    filter.unratedOnly = false
                                }
                            }
                            toggleChip("Unrated", on: filter.unratedOnly) { filter.unratedOnly.toggle(); filter.minRating = nil }
                        }
                    }
                    if !library.allGenres.isEmpty {
                        section("Genre") {
                            FlowLayout(spacing: 5) {
                                ForEach(library.allGenres.prefix(30), id: \.name) { g in
                                    toggleChip("\(g.name) \(g.count)", on: filter.genres.contains(g.name)) { toggle(&filter.genres, g.name) }
                                }
                            }
                        }
                    }
                    section("Author") {
                        VStack(alignment: .leading, spacing: 4) {
                            TextField("Find an author", text: $authorQuery).textFieldStyle(GlassFieldStyle())
                            let authors = library.allAuthors.filter { authorQuery.isEmpty || $0.localizedCaseInsensitiveContains(authorQuery) }
                            ForEach(authors.prefix(8), id: \.self) { a in
                                Toggle(a, isOn: Binding(get: { filter.authors.contains(a) }, set: { _ in toggle(&filter.authors, a) }))
                                    .toggleStyle(.checkbox)
                                    .font(DS.Text.callout)
                            }
                            if authors.count > 8 {
                                Text("\(authors.count - 8) more. Type to narrow.").font(DS.Text.micro).foregroundStyle(DS.textTertiary)
                            }
                        }
                    }
                    if !library.allTags.isEmpty {
                        section("Tags") {
                            FlowLayout(spacing: 5) {
                                ForEach(library.allTags, id: \.self) { t in
                                    toggleChip("#\(t)", on: filter.tags.contains(t)) { toggle(&filter.tags, t) }
                                }
                            }
                        }
                    }
                    if !library.shelves.isEmpty {
                        section("Shelves") {
                            FlowLayout(spacing: 5) {
                                ForEach(library.shelves) { s in
                                    toggleChip(s.name, on: filter.shelfIDs.contains(s.id)) { toggle(&filter.shelfIDs, s.id) }
                                }
                            }
                        }
                    }
                    section("Publication year") {
                        HStack {
                            TextField("From", value: $filter.publishedFrom, format: .number.grouping(.never)).textFieldStyle(GlassFieldStyle())
                            Text("–").foregroundStyle(DS.textTertiary)
                            TextField("To", value: $filter.publishedTo, format: .number.grouping(.never)).textFieldStyle(GlassFieldStyle())
                        }
                    }
                    section("Page count") {
                        HStack {
                            TextField("Min", value: $filter.minPages, format: .number).textFieldStyle(GlassFieldStyle())
                            Text("–").foregroundStyle(DS.textTertiary)
                            TextField("Max", value: $filter.maxPages, format: .number).textFieldStyle(GlassFieldStyle())
                        }
                    }
                    section("Date added") {
                        FlowLayout(spacing: 5) {
                            ForEach([(nil, "Any"), (7, "7 days"), (30, "30 days"), (90, "90 days"), (365, "Year")], id: \.1) { days, label in
                                toggleChip(label, on: filter.addedWithinDays == days) { filter.addedWithinDays = days }
                            }
                        }
                    }
                    if !completedYears.isEmpty {
                        section("Date completed") {
                            FlowLayout(spacing: 5) {
                                toggleChip("Any", on: filter.completedYear == nil) { filter.completedYear = nil }
                                ForEach(completedYears, id: \.self) { y in
                                    toggleChip(String(y), on: filter.completedYear == y) { filter.completedYear = filter.completedYear == y ? nil : y }
                                }
                            }
                        }
                    }
                }
                .padding(16)
            }
        }
        .frame(width: 340, height: 520)
    }

    private func section<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title.uppercased()).font(DS.Text.eyebrow).tracking(0.6).foregroundStyle(DS.textTertiary)
            content()
        }
    }

    private func toggleChip(_ label: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: { Motion.perform(Motion.gentle, action) }) {
            Text(label)
                .font(.system(size: 11, weight: on ? .semibold : .regular))
                .foregroundStyle(on ? DS.accent : DS.textSecondary)
                .padding(.horizontal, 9).padding(.vertical, 4.5)
                .background(Capsule().fill(on ? DS.selection : DS.fill))
                .overlay(Capsule().strokeBorder(on ? DS.accent.opacity(0.35) : DS.stroke))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private func toggle<T: Hashable>(_ set: inout Set<T>, _ v: T) {
        if set.contains(v) { set.remove(v) } else { set.insert(v) }
    }
}
