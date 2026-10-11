import SwiftUI

struct PaletteItem: Identifiable {
    enum Section: String, CaseIterable { case session = "Reading Session", recent = "Recent", actions = "Actions", go = "Go To", books = "Books", notes = "Notes" }
    let id: String
    let section: Section
    let title: String
    var subtitle: String?
    let icon: String
    /// When set, choosing the item asks for a number (e.g. a page) before running.
    var numberPrompt: String?
    var run: (Int?) -> Void
}

/// ⌘K: search everything and run any command from the keyboard.
struct CommandPalette: View {
    @EnvironmentObject var library: Library
    @EnvironmentObject var app: AppState
    @Environment(\.openSettings) private var openSettings
    @State private var query = ""
    @State private var selection = 0
    @State private var pending: PaletteItem?
    @State private var number = ""
    @FocusState private var focused: Bool

    private func matches(_ text: String) -> Bool {
        let tokens = query.lowercased().split(separator: " ")
        guard !tokens.isEmpty else { return true }
        let words = text.lowercased()
        return tokens.allSatisfy { words.contains($0) }
    }

    private var items: [PaletteItem] {
        var out: [PaletteItem] = []
        let q = query.trimmingCharacters(in: .whitespaces)

        // Live session controls first.
        if let s = library.activeSession, let b = library.book(s.bookID) {
            out.append(PaletteItem(id: "s-toggle", section: .session, title: s.isPaused ? "Resume Session" : "Pause Session",
                                   subtitle: b.title, icon: s.isPaused ? "play.fill" : "pause.fill") { _ in
                s.isPaused ? library.resumeSession() : library.pauseSession()
            })
            out.append(PaletteItem(id: "s-finish", section: .session, title: "Finish Session", subtitle: b.title, icon: "stop.fill",
                                   numberPrompt: "End page for \(b.title)") { page in library.finishSession(endPage: page) })
        }

        if q.isEmpty {
            for id in app.recentBooks.prefix(5) {
                guard let b = library.book(id) else { continue }
                out.append(PaletteItem(id: "r-\(id)", section: .recent, title: b.title, subtitle: b.authorLine, icon: "clock.arrow.circlepath") { _ in
                    app.openDetail(id)
                })
            }
        }

        var actions: [PaletteItem] = [
            PaletteItem(id: "a-add", section: .actions, title: "Add a Book", subtitle: "⌘N", icon: "plus") { _ in library.presentAddBook() },
            PaletteItem(id: "a-collection", section: .actions, title: "New Collection", icon: "rectangle.stack.badge.plus") { _ in
                app.editingShelf = Shelf(name: "", kind: .manual)
            },
            PaletteItem(id: "a-smart", section: .actions, title: "New Smart Shelf", icon: "sparkles") { _ in
                app.editingShelf = Shelf(name: "", icon: "sparkles", kind: .smart, rules: [ShelfRule(.rating, .atLeast, "4")])
            },
            PaletteItem(id: "a-import", section: .actions, title: "Import Goodreads Library", icon: "square.and.arrow.down") { _ in library.importGoodreads() },
            PaletteItem(id: "a-backup", section: .actions, title: "Export Complete Backup", icon: "externaldrive") { _ in library.exportFolioBackup() },
            PaletteItem(id: "a-markdown", section: .actions, title: "Export Notes as Markdown", icon: "doc.text") { _ in library.exportMarkdownNotes() },
            PaletteItem(id: "a-settings", section: .actions, title: "Open Settings", subtitle: "⌘,", icon: "gearshape") { _ in openSettings() },
        ]
        for b in library.books(in: .reading) {
            actions.append(PaletteItem(id: "a-page-\(b.id)", section: .actions, title: "Update Progress: \(b.title)",
                                       subtitle: "Currently page \(b.currentPage)\(b.pageCount.map { " of \($0)" } ?? "")",
                                       icon: "bookmark", numberPrompt: "Page you're on in \(b.title)") { page in
                if let page { library.logProgress(b.id, page: page) }
            })
            if library.activeSession?.bookID != b.id {
                actions.append(PaletteItem(id: "a-session-\(b.id)", section: .actions, title: "Start Reading Session: \(b.title)",
                                           icon: "play.fill") { _ in library.startSession(b.id) })
            }
        }
        out += actions.filter { matches($0.title) }

        let pages: [(Page, String)] = [(.home, "house"), (.books, "books.vertical"), (.knowledge, "brain.head.profile"),
                                       (.ask, "text.bubble"), (.discover, "safari"), (.stats, "chart.xyaxis.line")]
        var go: [PaletteItem] = pages.map { p, icon in
            PaletteItem(id: "g-\(p.rawValue)", section: .go, title: p.rawValue, icon: icon) { _ in app.go(p) }
        }
        go += ReadingStatus.allCases.map { s in
            PaletteItem(id: "g-s-\(s.rawValue)", section: .go, title: s.title, icon: s.symbol) { _ in app.show(.status(s)) }
        }
        go += library.shelves.map { s in
            PaletteItem(id: "g-shelf-\(s.id)", section: .go, title: s.name, subtitle: s.kind == .smart ? "Smart shelf" : "Collection", icon: s.icon) { _ in
                app.show(.shelf(s.id))
            }
        }
        go += library.allTags.map { t in
            PaletteItem(id: "g-tag-\(t)", section: .go, title: "#\(t)", subtitle: "Tag", icon: "number") { _ in app.show(.tag(t)) }
        }
        out += go.filter { matches($0.title) }.prefix(q.isEmpty ? 6 : 8)

        if !q.isEmpty {
            let hits = KeywordSearch.search(q, books: library.books, limit: 20, minCoverage: 0.5)
            for h in hits.prefix(14) {
                switch h.source {
                case .book(let id) where out.filter({ $0.section == .books }).count < 6:
                    out.append(PaletteItem(id: "b-\(id)", section: .books, title: h.title, subtitle: h.subtitle, icon: "book.closed") { _ in
                        app.openDetail(id)
                    })
                case .note(let nid, _) where out.filter({ $0.section == .notes }).count < 6:
                    out.append(PaletteItem(id: "n-\(nid)", section: .notes, title: h.snippet, subtitle: "\(h.title) · \(h.subtitle)",
                                           icon: h.noteKind?.symbol ?? "note.text") { _ in app.openNote(nid) })
                default: break
                }
            }
        }
        return out
    }

    var body: some View {
        let items = items
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: pending == nil ? "command" : "number")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(DS.accent)
                if let pending {
                    TextField(pending.numberPrompt ?? "", text: $number)
                        .textFieldStyle(.plain)
                        .font(.system(size: 17))
                        .focused($focused)
                        .onSubmit { complete(pending) }
                } else {
                    TextField("Search books and notes, or type a command…", text: $query)
                        .textFieldStyle(.plain)
                        .font(.system(size: 17))
                        .focused($focused)
                        .onSubmit { activate(items) }
                }
                Text("esc").font(.system(size: 10, weight: .semibold)).foregroundStyle(DS.textTertiary)
                    .padding(.horizontal, 5).padding(.vertical, 2)
                    .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(DS.stroke))
            }
            .padding(.horizontal, 16)
            .frame(height: 54)
            Divider().overlay(DS.stroke)
            if let pending {
                HStack {
                    Text("Type a number and press Return.")
                        .font(DS.Text.callout).foregroundStyle(DS.textSecondary)
                    Spacer()
                    Button("Cancel") { self.pending = nil; number = "" }.buttonStyle(GhostButtonStyle())
                    Button("Apply") { complete(pending) }
                        .buttonStyle(PrimaryButtonStyle(fullWidth: false))
                        .disabled(number.intValue == nil)
                }
                .padding(12)
            } else if items.isEmpty {
                Text("No matches").font(DS.Text.callout).foregroundStyle(DS.textTertiary).padding(20)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 1) {
                            ForEach(PaletteItem.Section.allCases, id: \.self) { section in
                                let rows = items.enumerated().filter { $0.element.section == section }
                                if !rows.isEmpty {
                                    Text(section.rawValue.uppercased())
                                        .font(DS.Text.eyebrow).tracking(0.7).foregroundStyle(DS.textTertiary)
                                        .padding(.horizontal, 14).padding(.top, 10).padding(.bottom, 3)
                                    ForEach(rows, id: \.element.id) { idx, item in
                                        row(item, selected: idx == selection)
                                            .id(idx)
                                            .onTapGesture { selection = idx; activate(items) }
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 6)
                        .padding(.bottom, 8)
                    }
                    .frame(maxHeight: 380)
                    .onChange(of: selection) { _, s in proxy.scrollTo(s, anchor: .center) }
                }
            }
        }
        .frame(width: 620)
        .background(VisualEffectView(material: .popover, blending: .withinWindow, state: .active))
        .background(DS.background.opacity(0.6))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(DS.strokeStrong))
        .shadow(color: .black.opacity(0.28), radius: 40, y: 18)
        .onAppear { focused = true }
        .onChange(of: query) { selection = 0 }
        .onChange(of: number) { _, n in
            // A pasted value ending in a newline submits, like Return.
            if n.contains("\n"), let p = pending { complete(p) }
        }
        .onKeyPress(.downArrow) { selection = min(selection + 1, max(0, items.count - 1)); return .handled }
        .onKeyPress(.upArrow) { selection = max(selection - 1, 0); return .handled }
        .onExitCommand { close() }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Command palette")
    }

    private func row(_ item: PaletteItem, selected: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: item.icon)
                .font(.system(size: 12))
                .frame(width: 22)
                .foregroundStyle(selected ? DS.accent : DS.textSecondary)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.title).font(.system(size: 13, weight: selected ? .semibold : .regular)).lineLimit(1)
                if let s = item.subtitle { Text(s).font(DS.Text.caption).foregroundStyle(DS.textTertiary).lineLimit(1) }
            }
            Spacer()
            if selected { Image(systemName: "return").font(.system(size: 10)).foregroundStyle(DS.textTertiary) }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 8).fill(selected ? DS.selection : .clear))
        .contentShape(Rectangle())
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }

    private func activate(_ items: [PaletteItem]) {
        guard items.indices.contains(selection) else { return }
        let item = items[selection]
        if item.numberPrompt != nil {
            pending = item
            number = ""
            DispatchQueue.main.async { focused = true }
        } else {
            close()
            item.run(nil)
        }
    }

    private func complete(_ item: PaletteItem) {
        guard let n = number.intValue else { return }
        close()
        item.run(n)
    }

    private func close() {
        app.paletteShown = false
        query = ""
        pending = nil
    }
}
