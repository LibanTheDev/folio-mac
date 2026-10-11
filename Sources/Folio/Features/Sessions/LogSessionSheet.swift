import SwiftUI

/// Manually record a past reading session.
struct LogSessionSheet: View {
    @EnvironmentObject var library: Library
    @Environment(\.dismiss) private var dismiss
    @State var bookID: UUID?
    @State private var start = Date().addingTimeInterval(-3600)
    @State private var minutes = "30"
    @State private var startPage = ""
    @State private var endPage = ""

    private var candidates: [Book] {
        library.books.filter { $0.status != .wantToRead }.sorted { $0.updatedAt > $1.updatedAt }
    }

    private var valid: Bool {
        guard bookID != nil, let m = Double(minutes.trimmingCharacters(in: .whitespaces)), m > 0, m < 24 * 60 else { return false }
        if let s = startPage.intValue, let e = endPage.intValue, e < s { return false }
        return start <= Date()
    }

    var body: some View {
        SheetContainer(title: "Log a Reading Session", subtitle: "Record reading you did earlier. It counts toward your time, streaks and pace.") {
            VStack(alignment: .leading, spacing: 12) {
                FieldRow(label: "Book") {
                    Picker("Book", selection: $bookID) {
                        Text("Choose a book").tag(UUID?.none)
                        ForEach(candidates) { b in Text(b.title).tag(UUID?.some(b.id)) }
                    }
                    .labelsHidden()
                }
                HStack(spacing: 12) {
                    FieldRow(label: "Started") {
                        DatePicker("", selection: $start, in: ...Date(), displayedComponents: [.date, .hourAndMinute])
                            .labelsHidden()
                    }
                    FieldRow(label: "Minutes read") {
                        TextField("30", text: $minutes).textFieldStyle(GlassFieldStyle()).frame(width: 80)
                    }
                }
                HStack(spacing: 12) {
                    FieldRow(label: "From page (optional)") {
                        TextField("—", text: $startPage).textFieldStyle(GlassFieldStyle()).frame(width: 110)
                    }
                    FieldRow(label: "To page (optional)") {
                        TextField("—", text: $endPage).textFieldStyle(GlassFieldStyle()).frame(width: 110)
                    }
                }
                if let s = startPage.intValue, let e = endPage.intValue, e < s {
                    Text("The end page must be after the start page.").font(DS.Text.caption).foregroundStyle(DS.statusDNF)
                }
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 18)
        } footer: {
            Spacer()
            Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction).buttonStyle(GlassButtonStyle())
            Button("Save Session") {
                guard let id = bookID, let m = Double(minutes.trimmingCharacters(in: .whitespaces)) else { return }
                library.addManualSession(bookID: id, start: start, minutes: m, startPage: startPage.intValue, endPage: endPage.intValue)
                dismiss()
            }
            .keyboardShortcut(.defaultAction)
            .buttonStyle(PrimaryButtonStyle(fullWidth: false))
            .disabled(!valid)
        }
        .frame(width: 480)
        .onAppear {
            if bookID == nil { bookID = library.books(in: .reading).first?.id ?? candidates.first?.id }
            if let b = bookID.flatMap(library.book) { startPage = String(b.currentPage) }
        }
    }
}

/// Recent sessions with delete, for one book or the whole library.
struct SessionList: View {
    @EnvironmentObject var library: Library
    var bookID: UUID?
    var limit = 8

    var body: some View {
        let sessions = (bookID.map { library.sessions(for: $0) } ?? library.sessions.sorted { $0.start > $1.start }).prefix(limit)
        VStack(alignment: .leading, spacing: 0) {
            if sessions.isEmpty {
                Text("No sessions recorded yet.").font(DS.Text.callout).foregroundStyle(DS.textTertiary)
            }
            ForEach(Array(sessions)) { s in
                HStack(spacing: 10) {
                    Image(systemName: s.isManual ? "square.and.pencil" : "timer")
                        .font(.system(size: 11)).foregroundStyle(DS.textTertiary).frame(width: 16)
                        .help(s.isManual ? "Logged manually" : "Timed session")
                    VStack(alignment: .leading, spacing: 1) {
                        if bookID == nil, let b = library.book(s.bookID) {
                            Text(b.title).font(DS.Text.callout.weight(.medium)).lineLimit(1)
                        }
                        Text(s.start.formatted(date: .abbreviated, time: .shortened))
                            .font(DS.Text.caption).foregroundStyle(DS.textSecondary)
                    }
                    Spacer()
                    Text(s.duration.readingDuration).font(DS.Text.callout.monospacedDigit())
                    if s.pagesRead > 0 {
                        Text("\(s.pagesRead) pp").font(DS.Text.caption.monospacedDigit()).foregroundStyle(DS.textSecondary)
                            .frame(width: 44, alignment: .trailing)
                    }
                    Button { library.deleteSession(s.id) } label: { Image(systemName: "trash").font(.system(size: 10)) }
                        .buttonStyle(IconButtonStyle(size: 22))
                        .help("Delete session")
                        .accessibilityLabel("Delete session")
                }
                .padding(.vertical, 6)
                Rectangle().fill(DS.stroke).frame(height: 1)
            }
        }
    }
}
