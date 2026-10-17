import SwiftUI

/// States plainly where a book's progress figure comes from.
struct ProgressSourceLabel: View {
    let book: Book

    var body: some View {
        switch book.progressProvenance {
        case .loggedInFolio:
            Label("Logged in Folio", systemImage: "pencil.and.list.clipboard")
                .foregroundStyle(DS.textTertiary)
        case .confirmedByAppleBooks:
            Label(appleText, systemImage: "checkmark.seal")
                .foregroundStyle(DS.statusRead)
                .help("Read from Apple Books on this Mac. Progress synced from your iPad arrives through iCloud.")
        case .unknown:
            Label("Progress unknown", systemImage: "questionmark.circle")
                .foregroundStyle(DS.textTertiary)
                .help("No page has been logged in Folio and no confirmed position is available from Apple Books.")
        }
    }

    private var appleText: String {
        guard let e = book.externalProgress else { return "Apple Books" }
        let when = e.observedAt.formatted(.relative(presentation: .named))
        return e.finished ? "Finished in Apple Books" : "Confirmed by Apple Books · \(Int((e.fraction * 100).rounded()))% · \(when)"
    }
}

/// Small badge marking content imported from Apple Books.
struct AppleBooksBadge: View {
    var text = "Apple Books"
    var body: some View {
        Label(text, systemImage: "apple.logo")
            .font(.system(size: 9.5, weight: .semibold))
            .foregroundStyle(DS.textSecondary)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(Capsule().fill(DS.fill))
            .overlay(Capsule().strokeBorder(DS.stroke))
    }
}
