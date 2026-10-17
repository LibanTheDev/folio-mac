import AppKit
import SwiftUI

/// Matching EPUB editions from open-licence catalogs, shown inside the Discover book modal.
struct FindEpubPanel: View {
    @EnvironmentObject var library: Library
    @StateObject private var downloads = EbookDownloads.shared
    let doc: OLDoc
    @State private var result: EbookSearch.Result?

    private var query: EbookQuery {
        EbookQuery(title: doc.title, author: doc.author_name?.first, isbn: doc.preferredISBN)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Free EPUB editions").font(DS.Text.sectionTitle)
                Spacer()
                Text("Standard Ebooks · Project Gutenberg").font(DS.Text.caption).foregroundStyle(DS.textTertiary)
            }
            if let result {
                if result.editions.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("No free, legal EPUB found for this book.").font(DS.Text.callout.weight(.medium))
                        Text("Folio only offers editions that are in the public domain or openly licensed. Most books published in the last century are still under copyright. Look for them in Apple Books or your library's lending app.")
                            .font(DS.Text.caption).foregroundStyle(DS.textSecondary)
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .glass(.card, cornerRadius: DS.Radius.card)
                } else {
                    VStack(spacing: 10) {
                        ForEach(result.editions) { EditionRow(edition: $0, onDone: link) }
                    }
                }
                if !result.failedProviders.isEmpty {
                    Label("Couldn't reach \(result.failedProviders.map(\.displayName).joined(separator: " and ")). Results may be incomplete.",
                          systemImage: "wifi.exclamationmark")
                        .font(DS.Text.caption).foregroundStyle(DS.textTertiary)
                }
            } else {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Searching open catalogs…").font(DS.Text.callout).foregroundStyle(DS.textSecondary)
                }
            }
            Text("Downloads are saved in Folio's Ebooks folder and linked to the book (added to Want to Read if it isn't in your library yet). Open them in Apple Books to read; Folio's Apple Books sync then keeps progress and highlights in step.")
                .font(DS.Text.micro).foregroundStyle(DS.textTertiary)
        }
        .task(id: doc.key) { result = await EbookSearch.find(query) }
    }

    /// Links a finished download to the book, adding the book to Want to Read if needed.
    private func link(_ edition: EbookEdition) {
        guard let ebook = downloads.localEbook(for: edition) else { return }
        let id = library.existing(matching: Book(from: doc))?.id ?? library.add(Book(from: doc), status: .wantToRead)
        library.modify(id) { b in if b.ebook?.sha256 != ebook.sha256 { b.ebook = ebook } }
    }
}

private struct EditionRow: View {
    @StateObject private var downloads = EbookDownloads.shared
    let edition: EbookEdition
    let onDone: (EbookEdition) -> Void

    var body: some View {
        let state = downloads.state(for: edition)
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: edition.provider == .standardEbooks ? "book.closed.fill" : "building.columns.fill")
                .font(.system(size: 14))
                .foregroundStyle(DS.accent)
                .frame(width: 30, height: 30)
                .background(Circle().fill(DS.selection))
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(edition.provider.displayName).font(DS.Text.eyebrow).textCase(.uppercase).tracking(0.5).foregroundStyle(DS.textTertiary)
                    Chip(text: "Public domain")
                }
                Text(edition.title).font(.system(size: 13, weight: .semibold)).lineLimit(2)
                Text(edition.authors.joined(separator: ", ")).font(DS.Text.caption).foregroundStyle(DS.textSecondary)
                Text(details).font(DS.Text.caption).foregroundStyle(DS.textSecondary)
                Text(edition.rights).font(DS.Text.micro).foregroundStyle(DS.textTertiary).lineLimit(2)
                    .help(edition.rights)
                stateView(state)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 6) {
                actions(state)
                Link(destination: edition.listingURL) { Label("View Listing", systemImage: "safari") }
                    .font(DS.Text.caption)
                    .help("Open this edition's page at \(edition.provider.displayName)")
            }
        }
        .padding(14)
        .glass(.card, cornerRadius: DS.Radius.card)
        .onChange(of: state) { _, new in if case .done = new { onDone(edition) } }
    }

    private var details: String {
        var parts = [edition.formatLabel]
        if let l = edition.language { parts.append(Locale.current.localizedString(forLanguageCode: l) ?? l) }
        if let y = edition.year { parts.append(String(y)) }
        if let s = edition.fileSize { parts.append(ByteCountFormatter.string(fromByteCount: s, countStyle: .file)) }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder private func stateView(_ state: EbookDownloads.State?) -> some View {
        switch state {
        case .downloading(let p)?:
            HStack(spacing: 8) {
                if let p { ProgressBar(value: p, height: 4).frame(width: 160) } else { ProgressView().controlSize(.mini) }
                Text(p.map { "\(Int($0 * 100))%" } ?? "Downloading…").font(DS.Text.micro.monospacedDigit()).foregroundStyle(DS.textTertiary)
            }
            .padding(.top, 2)
        case .retrying(let attempt)?:
            Label("Connection problem, retrying (attempt \(attempt) of \(RetryPolicy.maxAttempts))…", systemImage: "arrow.clockwise")
                .font(DS.Text.micro).foregroundStyle(DS.statusReading)
        case .validating?:
            Label("Checking the EPUB…", systemImage: "checkmark.shield").font(DS.Text.micro).foregroundStyle(DS.textTertiary)
        case .failed(let message)?:
            Label(message, systemImage: "exclamationmark.triangle").font(DS.Text.micro).foregroundStyle(DS.statusDNF)
        case .cancelled?:
            Text("Download cancelled.").font(DS.Text.micro).foregroundStyle(DS.textTertiary)
        case .done?:
            Label("Saved and verified", systemImage: "checkmark.circle.fill").font(DS.Text.micro).foregroundStyle(DS.statusRead)
        case nil:
            EmptyView()
        }
    }

    @ViewBuilder private func actions(_ state: EbookDownloads.State?) -> some View {
        switch state {
        case .downloading?, .retrying?, .validating?:
            Button("Cancel") { downloads.cancel(edition) }.buttonStyle(GlassButtonStyle())
        case .done(let url)?:
            Button { EbookDownloads.openInAppleBooks(url) } label: { Label("Open in Apple Books", systemImage: "book") }
                .buttonStyle(PrimaryButtonStyle(fullWidth: false))
            Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                .buttonStyle(GhostButtonStyle())
        case .failed?, .cancelled?:
            Button { downloads.download(edition) } label: { Label("Try Again", systemImage: "arrow.clockwise") }
                .buttonStyle(GlassButtonStyle())
        case nil:
            Button { downloads.download(edition) } label: { Label("Download EPUB", systemImage: "arrow.down.circle") }
                .buttonStyle(PrimaryButtonStyle(fullWidth: false))
        }
    }
}
