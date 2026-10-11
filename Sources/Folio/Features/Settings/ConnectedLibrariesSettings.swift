import AppKit
import SwiftUI

struct ConnectedLibrariesSettings: View {
    @EnvironmentObject var library: Library
    @EnvironmentObject var sync: AppleBooksSync

    var body: some View {
        Form {
            Section {
                HStack(alignment: .top, spacing: 14) {
                    Image(systemName: "books.vertical.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(LinearGradient(colors: [Color(red: 1, green: 0.62, blue: 0.2), Color(red: 0.95, green: 0.42, blue: 0.1)],
                                                 startPoint: .top, endPoint: .bottom)))
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Apple Books").font(.headline)
                        HStack(spacing: 6) {
                            Circle().fill(statusColor).frame(width: 8, height: 8)
                            Text(sync.status.title).font(.callout)
                        }
                        if let last = sync.lastSync {
                            Text("Last synced \(last.formatted(date: .abbreviated, time: .shortened)) (\(last.formatted(.relative(presentation: .named))))")
                                .font(.caption).foregroundStyle(.secondary)
                        } else {
                            Text("Not synced yet").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    Toggle("", isOn: $sync.enabled).toggleStyle(.switch).labelsHidden()
                        .accessibilityLabel("Sync with Apple Books")
                }
                if let detail = sync.status.detail {
                    Text(detail).font(.caption).foregroundStyle(.secondary)
                }
                if sync.status == .permissionNeeded {
                    Button("Open Privacy & Security Settings") {
                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!)
                    }
                }
                HStack {
                    Button(sync.status == .syncing ? "Syncing…" : "Sync Now") { sync.sync(force: true) }
                        .disabled(!sync.enabled || sync.status == .syncing)
                    Spacer()
                }
            }

            if sync.enabled {
                Section("In Folio") {
                    LabeledContent("Books linked to Apple Books", value: "\(sync.linkedBookCount)")
                    LabeledContent("Confirmed reading progress", value: "\(sync.confirmedProgressCount) books")
                    LabeledContent("Imported highlights & notes", value: "\(sync.importedHighlightCount)")
                }
                if let s = sync.lastSummary {
                    Section("Last sync") {
                        LabeledContent("Books in Apple Books", value: "\(s.booksSeen)")
                        if s.booksAdded > 0 { LabeledContent("New books added", value: "\(s.booksAdded)") }
                        if s.booksLinked > 0 { LabeledContent("Matched to existing Folio books", value: "\(s.booksLinked)") }
                        if s.statusUpgraded > 0 { LabeledContent("Statuses moved forward", value: "\(s.statusUpgraded)") }
                        if s.highlightsAdded + s.highlightsUpdated + s.highlightsRemoved > 0 {
                            LabeledContent("Highlights added / updated / removed", value: "\(s.highlightsAdded) / \(s.highlightsUpdated) / \(s.highlightsRemoved)")
                        }
                        if s.highlightsKeptLocalEdits > 0 { LabeledContent("Highlights kept with your Folio edits", value: "\(s.highlightsKeptLocalEdits)") }
                        if s.highlightsUnmatched > 0 {
                            LabeledContent("Highlights for books no longer in Apple Books", value: "\(s.highlightsUnmatched) (skipped)")
                        }
                        if s.skippedSamplesOrHidden + s.skippedAudiobooks > 0 {
                            LabeledContent("Samples, hidden items & audiobooks skipped", value: "\(s.skippedSamplesOrHidden + s.skippedAudiobooks)")
                        }
                        if !s.annotationsAvailable {
                            Text("Highlights weren't available in this sync (annotation store missing or changed). Books and progress still synced.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Section("How it works") {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Apple Books on iPad → iCloud → Apple Books on this Mac → Folio")
                        .font(.callout.weight(.medium))
                    Text("Folio reads a private copy of Apple Books' library and highlight databases, never the originals, and never writes to them. New books and highlights appear automatically; reading position and completion are shown as confirmed only when Apple Books records them. Your Folio ratings, notes, collections and edits are never overwritten.")
                        .font(.caption).foregroundStyle(.secondary)
                    Text("Apple Books' databases are undocumented and may change with macOS updates. If that happens, Folio pauses syncing and leaves your library untouched.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .padding(.vertical, 8)
    }

    private var statusColor: Color {
        switch sync.status {
        case .connected: .green
        case .syncing, .idle: .blue
        case .off: .gray
        case .permissionNeeded, .notFound: .orange
        case .schemaUnsupported, .error: .red
        }
    }
}
