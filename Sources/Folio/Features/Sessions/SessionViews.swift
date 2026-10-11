import SwiftUI

/// Live controls for the active reading session.
struct SessionBanner: View {
    @EnvironmentObject var library: Library
    @EnvironmentObject var app: AppState
    let session: ActiveSession
    @State private var finishing = false
    @State private var endPage = ""

    var body: some View {
        if let book = library.book(session.bookID) {
            HStack(spacing: 14) {
                CoverView(book: book).frame(width: 40)
                VStack(alignment: .leading, spacing: 3) {
                    Text(session.isPaused ? "SESSION PAUSED" : "READING NOW")
                        .font(DS.Text.eyebrow).tracking(0.8)
                        .foregroundStyle(session.isPaused ? DS.textTertiary : DS.accent)
                    Text(book.title).font(DS.Text.headline).lineLimit(1)
                    Text("Started on page \(session.startPage)\(book.pageCount.map { " of \($0)" } ?? "")")
                        .font(DS.Text.caption).foregroundStyle(DS.textSecondary)
                }
                Spacer()
                TimelineView(.periodic(from: .now, by: 1)) { ctx in
                    Text(Self.clock(session.elapsed(at: ctx.date)))
                        .font(.system(size: 26, weight: .medium, design: .rounded).monospacedDigit())
                        .contentTransition(.numericText())
                        .foregroundStyle(session.isPaused ? DS.textSecondary : DS.textPrimary)
                }
                HStack(spacing: 6) {
                    Button { session.isPaused ? library.resumeSession() : library.pauseSession() } label: {
                        Image(systemName: session.isPaused ? "play.fill" : "pause.fill")
                    }
                    .buttonStyle(IconButtonStyle(size: 32))
                    .help(session.isPaused ? "Resume" : "Pause")
                    .accessibilityLabel(session.isPaused ? "Resume session" : "Pause session")
                    Button("Finish") { endPage = String(book.currentPage); finishing = true }
                        .buttonStyle(PrimaryButtonStyle(fullWidth: false))
                        .popover(isPresented: $finishing, arrowEdge: .bottom) {
                            FinishSessionForm(book: book, endPage: $endPage) { page in
                                library.finishSession(endPage: page)
                                finishing = false
                            } onDiscard: {
                                library.discardSession()
                                finishing = false
                            }
                        }
                }
            }
            .padding(14)
            .glass(.card, cornerRadius: DS.Radius.card, selected: !session.isPaused)
            .contentShape(Rectangle())
            .onTapGesture { app.openDetail(book.id) }
        }
    }

    static func clock(_ t: TimeInterval) -> String {
        let s = Int(t)
        return s >= 3600 ? String(format: "%d:%02d:%02d", s / 3600, s / 60 % 60, s % 60) : String(format: "%d:%02d", s / 60, s % 60)
    }
}

struct FinishSessionForm: View {
    let book: Book
    @Binding var endPage: String
    let onFinish: (Int?) -> Void
    let onDiscard: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Finish session").font(DS.Text.headline)
            Text("What page did you reach?").font(DS.Text.callout).foregroundStyle(DS.textSecondary)
            HStack {
                TextField("Page", text: $endPage)
                    .textFieldStyle(GlassFieldStyle())
                    .frame(width: 80)
                    .onSubmit { onFinish(endPage.intValue) }
                if let p = book.pageCount { Text("of \(p)").foregroundStyle(DS.textSecondary) }
            }
            HStack {
                Button("Discard", role: .destructive, action: onDiscard).buttonStyle(GhostButtonStyle())
                Spacer()
                Button("Save Session") { onFinish(endPage.intValue) }
                    .buttonStyle(PrimaryButtonStyle(fullWidth: false))
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
        .frame(width: 260)
    }
}

/// Compact session indicator for the top bar.
struct SessionPill: View {
    @EnvironmentObject var library: Library
    @EnvironmentObject var app: AppState
    let session: ActiveSession

    var body: some View {
        Button { app.openDetail(session.bookID) } label: {
            HStack(spacing: 6) {
                Circle()
                    .fill(session.isPaused ? DS.textTertiary : DS.statusRead)
                    .frame(width: 7, height: 7)
                TimelineView(.periodic(from: .now, by: 1)) { ctx in
                    Text(SessionBanner.clock(session.elapsed(at: ctx.date)))
                        .font(.system(size: 11.5, weight: .semibold).monospacedDigit())
                }
                if let b = library.book(session.bookID) {
                    Text(b.title).font(DS.Text.caption).foregroundStyle(DS.textSecondary).lineLimit(1).frame(maxWidth: 120)
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 26)
            .glass(.control, cornerRadius: 13)
        }
        .buttonStyle(.plain)
        .help("Reading session in progress")
        .accessibilityLabel("Reading session in progress")
    }
}
