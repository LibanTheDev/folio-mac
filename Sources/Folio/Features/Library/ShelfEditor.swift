import SwiftUI

struct ShelfEditor: View {
    @EnvironmentObject var library: Library
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss
    @State var draft: Shelf

    private let icons = ["books.vertical", "sparkles", "star", "trophy", "heart", "bookmark", "flame", "leaf",
                         "briefcase", "chart.line.uptrend.xyaxis", "person.text.rectangle", "globe", "brain",
                         "graduationcap", "building.columns", "airplane", "moon.stars", "ruler", "checkmark.seal",
                         "hand.raised", "arrow.counterclockwise", "lightbulb", "music.note", "paintbrush"]

    private var isNew: Bool { library.shelf(draft.id) == nil }
    private var matching: [Book] {
        draft.kind == .smart ? library.books.filter { draft.contains($0) } : library.books(on: draft)
    }

    var body: some View {
        SheetContainer(title: isNew ? (draft.kind == .smart ? "New Smart Shelf" : "New Collection") : "Edit Shelf",
                       subtitle: draft.kind == .smart ? "Smart shelves fill themselves and stay up to date as your library changes."
                                                     : "Collections hold exactly the books you add, in your order.") {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    FieldRow(label: "Name") {
                        TextField(draft.kind == .smart ? "e.g. Best Books of \(library.currentYear)" : "e.g. Business Biographies",
                                  text: $draft.name)
                            .textFieldStyle(GlassFieldStyle())
                    }
                    FieldRow(label: "Icon") {
                        LazyVGrid(columns: Array(repeating: GridItem(.fixed(30), spacing: 6), count: 12), alignment: .leading, spacing: 6) {
                            ForEach(icons, id: \.self) { icon in
                                Button { draft.icon = icon } label: { Image(systemName: icon) }
                                    .buttonStyle(IconButtonStyle(selected: draft.icon == icon, size: 30))
                                    .accessibilityLabel(icon)
                            }
                        }
                    }
                    if isNew {
                        FieldRow(label: "Type") {
                            GlassSegmented(selection: $draft.kind, options: [Shelf.Kind.manual, .smart]) { k in
                                Text(k == .manual ? "Collection" : "Smart Shelf")
                            }
                        }
                    }
                    if draft.kind == .smart { rulesEditor }
                    preview
                }
                .padding(.horizontal, 22)
                .padding(.bottom, 18)
            }
            .frame(maxHeight: 460)
        } footer: {
            if draft.kind == .smart, isNew {
                Menu("Templates") {
                    ForEach(Shelf.templates(year: library.currentYear), id: \.name) { t in
                        Button(t.name) {
                            draft.name = t.name; draft.icon = t.icon; draft.rules = t.rules; draft.matchAll = t.matchAll
                        }
                    }
                }
                .menuStyle(.button)
                .buttonStyle(GlassButtonStyle())
                .fixedSize()
            }
            Spacer()
            Button("Cancel") { dismiss() }
                .keyboardShortcut(.cancelAction)
                .buttonStyle(GlassButtonStyle())
            Button(isNew ? "Create Shelf" : "Save") { save() }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(PrimaryButtonStyle(fullWidth: false))
                .disabled(draft.name.trimmingCharacters(in: .whitespaces).isEmpty || (draft.kind == .smart && draft.rules.isEmpty))
        }
        .frame(width: 560)
    }

    private var rulesEditor: some View {
        FieldRow(label: "Rules") {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Text("Include books matching").font(DS.Text.callout).foregroundStyle(DS.textSecondary)
                    GlassSegmented(selection: $draft.matchAll, options: [true, false]) { Text($0 ? "all" : "any") }
                    Text("of these rules:").font(DS.Text.callout).foregroundStyle(DS.textSecondary)
                }
                ForEach($draft.rules) { $rule in
                    RuleRow(rule: $rule) { draft.rules.removeAll { $0.id == rule.id } }
                }
                Button { draft.rules.append(ShelfRule(.genre, .contains, "")) } label: {
                    Label("Add Rule", systemImage: "plus")
                }
                .buttonStyle(GhostButtonStyle())
            }
        }
    }

    private var preview: some View {
        let books = matching
        return FieldRow(label: "\(books.count) book\(books.count == 1 ? "" : "s") on this shelf") {
            if books.isEmpty {
                Text(draft.kind == .smart ? "No books match these rules yet." : "Add books from any book's menu or by dragging them onto the shelf.")
                    .font(DS.Text.callout).foregroundStyle(DS.textTertiary)
            } else {
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(books.prefix(20)) { b in CoverView(book: b).frame(width: 46).help(b.title) }
                    }
                    .padding(.vertical, 4)
                }
                .scrollIndicators(.never)
            }
        }
    }

    private func save() {
        draft.name = draft.name.trimmingCharacters(in: .whitespaces)
        draft.rules.removeAll { $0.value.trimmingCharacters(in: .whitespaces).isEmpty && $0.field != .favorite }
        if isNew {
            library.addShelf(draft)
            app.show(.shelf(draft.id))
        } else {
            library.updateShelf(draft)
        }
        dismiss()
    }
}

private struct RuleRow: View {
    @Binding var rule: ShelfRule
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Picker("Field", selection: Binding(get: { rule.field }, set: { f in
                rule.field = f
                if !f.allowedOps.contains(rule.op) { rule.op = f.allowedOps[0] }
                if f == .status { rule.value = ReadingStatus.read.rawValue }
                if f == .favorite { rule.value = "true" }
            })) {
                ForEach(ShelfRule.Field.allCases) { Text($0.title).tag($0) }
            }
            .labelsHidden()
            .frame(width: 170)
            Picker("Operator", selection: $rule.op) {
                ForEach(rule.field.allowedOps) { Text($0.title).tag($0) }
            }
            .labelsHidden()
            .frame(width: 120)
            valueEditor
            Button(action: onDelete) { Image(systemName: "minus.circle") }
                .buttonStyle(IconButtonStyle())
                .accessibilityLabel("Remove rule")
        }
        .controlSize(.small)
    }

    @ViewBuilder private var valueEditor: some View {
        switch rule.field {
        case .status:
            Picker("Value", selection: $rule.value) {
                ForEach(ReadingStatus.allCases) { Text($0.title).tag($0.rawValue) }
            }
            .labelsHidden()
        case .favorite:
            Picker("Value", selection: $rule.value) {
                Text("Yes").tag("true")
                Text("No").tag("false")
            }
            .labelsHidden()
        default:
            TextField(rule.field.isNumeric ? "Number" : "Text", text: $rule.value)
                .textFieldStyle(GlassFieldStyle())
        }
    }
}
