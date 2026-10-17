import AppKit
import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettings().tabItem { Label("General", systemImage: "gearshape") }
            ConnectedLibrariesSettings().tabItem { Label("Connected Libraries", systemImage: "books.vertical") }
            RemindersSettings().tabItem { Label("Reminders", systemImage: "bell") }
            AISettingsView().tabItem { Label("AI", systemImage: "sparkles") }
        }
        .frame(width: 620, height: 660)
        .tint(DS.accent)
    }
}

private struct GeneralSettings: View {
    @EnvironmentObject var library: Library
    @AppStorage("appearance") private var appearance = Appearance.system
    @AppStorage("backup.icloud") private var icloudBackup = false
    @State private var backupStatus: String?

    var body: some View {
        Form {
            Picker("Appearance", selection: $appearance) {
                ForEach(Appearance.allCases) { Text($0.title).tag($0) }
            }
            Section("iCloud Drive backup") {
                if CloudBackup.isAvailable {
                    Toggle("Keep daily backups in iCloud Drive", isOn: $icloudBackup)
                    HStack {
                        Button("Back Up Now") { backupNow() }
                        if let backupStatus { Text(backupStatus).font(.caption).foregroundStyle(.secondary) }
                    }
                    Text("Saves a dated copy of your library to “iCloud Drive › Folio Backups” once a day (the last 30 are kept), so you can restore on another Mac with File › Restore from Folio Backup. This is a backup, not live sync: see the roadmap for why.")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    Text("iCloud Drive isn't turned on for this Mac. Turn it on in System Settings to keep off-Mac backups.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Section("Your data") {
                LabeledContent("Library file") {
                    Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([library.store.fileURL]) }
                }
                LabeledContent("Backups") {
                    Button("Open Backups Folder") {
                        try? FileManager.default.createDirectory(at: library.store.backupsURL, withIntermediateDirectories: true)
                        NSWorkspace.shared.open(library.store.backupsURL)
                    }
                }
                Text("Folio keeps a daily backup (last 14 days) and a copy before every migration or restore.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding(.vertical, 8)
    }

    private func backupNow() {
        do {
            let data = try LibraryStore.encoder().encode(library.snapshot)
            if let url = try CloudBackup.backup(data) { backupStatus = "Saved \(url.lastPathComponent)" }
        } catch {
            backupStatus = error.localizedDescription
        }
    }
}

private struct RemindersSettings: View {
    @EnvironmentObject var library: Library
    @AppStorage("reminders.enabled") private var enabled = false
    @AppStorage("reminders.hour") private var hour = 21
    @AppStorage("reminders.minute") private var minute = 0
    @AppStorage("reminders.weekdays") private var weekdaysRaw = "1,2,3,4,5,6,7"
    @State private var status: String?

    private var weekdays: Set<Int> { Set(weekdaysRaw.split(separator: ",").compactMap { Int($0) }) }

    private var time: Binding<Date> {
        Binding(get: { Calendar.current.date(from: DateComponents(hour: hour, minute: minute)) ?? Date() },
                set: { d in
                    let c = Calendar.current.dateComponents([.hour, .minute], from: d)
                    hour = c.hour ?? 21; minute = c.minute ?? 0
                })
    }

    var body: some View {
        Form {
            Section {
                Toggle("Remind me to read", isOn: $enabled)
                DatePicker("Time", selection: time, displayedComponents: .hourAndMinute).disabled(!enabled)
                HStack(spacing: 4) {
                    ForEach(1...7, id: \.self) { d in
                        let on = weekdays.contains(d)
                        Button(Calendar.current.veryShortWeekdaySymbols[d - 1]) {
                            var set = weekdays
                            if on { set.remove(d) } else { set.insert(d) }
                            weekdaysRaw = set.sorted().map(String.init).joined(separator: ",")
                        }
                        .buttonStyle(.bordered)
                        .tint(on ? .accentColor : .secondary)
                        .accessibilityAddTraits(on ? .isSelected : [])
                    }
                }
                .disabled(!enabled)
                if let status { Text(status).font(.caption).foregroundStyle(.secondary) }
                Text("Reminders mention what you're currently reading and your streak, and are delivered by macOS even when Folio is closed.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding(.vertical, 8)
        .onChange(of: enabled) { reschedule() }
        .onChange(of: hour) { reschedule() }
        .onChange(of: minute) { reschedule() }
        .onChange(of: weekdaysRaw) { reschedule() }
    }

    private func reschedule() {
        let reading = library.books(in: .reading).map(\.title)
        let streak = Activity.currentStreak(Activity.daily(books: library.books, sessions: library.sessions))
        Task {
            let ok = await Reminders.schedule(enabled: enabled, hour: hour, minute: minute, weekdays: weekdays,
                                              currentlyReading: reading, streak: streak)
            status = !enabled ? "Reminders are off." : ok ? "Scheduled on \(weekdays.count) day\(weekdays.count == 1 ? "" : "s") a week." : "Notifications are blocked. Allow Folio in System Settings › Notifications."
        }
    }
}

private struct AISettingsView: View {
    @EnvironmentObject var library: Library
    @StateObject private var ai = AISettings.shared
    @State private var keyInput = ""
    @State private var testState: String?
    @State private var testing = false
    @State private var interestInput = ""

    var body: some View {
        Form {
            Section {
                Toggle("Enable AI features", isOn: $ai.enabled)
                Text("Off by default. When on, AI recommendations and Ask Folio send your question, plus only the data you allow below, to the provider you choose. Search, notes, analytics and semantic matching always run on this Mac.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Provider") {
                Picker("Provider", selection: $ai.provider) {
                    ForEach(AISettings.ProviderKind.allCases) { Text($0.title).tag($0) }
                }
                if ai.provider == .anthropic {
                    TextField("Model", text: $ai.anthropicModel)
                } else {
                    TextField("Server URL", text: $ai.compatibleBaseURL)
                    TextField("Model", text: $ai.compatibleModel)
                    Text("Works with local servers such as Ollama (http://localhost:11434/v1) or LM Studio, which keep everything on this Mac.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                LabeledContent(ai.provider == .anthropic ? "API key" : "API key (optional)") {
                    if ai.hasKey {
                        HStack {
                            Label("Stored in Keychain", systemImage: "lock.fill").foregroundStyle(.secondary)
                            Button("Remove") { ai.removeKey() }
                        }
                    } else {
                        HStack {
                            SecureField("Paste key", text: $keyInput).frame(width: 220)
                            Button("Save") {
                                try? ai.saveKey(keyInput)
                                keyInput = ""
                            }
                            .disabled(keyInput.trimmingCharacters(in: .whitespaces).isEmpty)
                        }
                    }
                }
                HStack {
                    Button(testing ? "Testing…" : "Test Connection", action: test).disabled(testing || !ai.enabled)
                    if let testState { Text(testState).font(.caption).foregroundStyle(.secondary).lineLimit(2) }
                }
            }
            Section("What may be shared") {
                Toggle("Book titles, authors, ratings and shelves", isOn: $ai.shareLibrary)
                Toggle("Notes, highlights and reflections", isOn: $ai.shareNotes)
                Text("Ask Folio needs notes to answer questions about what you've learned. Only passages relevant to each question are sent, never your whole vault.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Interests") {
                FlowLayout(spacing: 5) {
                    ForEach(library.interests, id: \.self) { i in
                        HStack(spacing: 4) {
                            Text(i)
                            Button { library.interests.removeAll { $0 == i } } label: { Image(systemName: "xmark").font(.system(size: 8, weight: .bold)) }
                                .buttonStyle(.plain)
                        }
                        .font(.caption)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Capsule().fill(.quaternary))
                    }
                }
                TextField("Add an interest (e.g. capital allocation)", text: $interestInput)
                    .onSubmit {
                        let t = interestInput.trimmingCharacters(in: .whitespaces)
                        if !t.isEmpty, !library.interests.contains(t) { library.interests.append(t) }
                        interestInput = ""
                    }
                Text("Used to tailor recommendations.").font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding(.vertical, 8)
    }

    private func test() {
        testing = true
        testState = nil
        Task {
            do {
                let provider = try ai.makeProvider()
                let r = try await provider.complete(AIRequest(
                    system: "You are a connectivity check.",
                    user: "Reply with ok set to true.",
                    schema: ["type": "object", "properties": ["ok": ["type": "boolean"]], "required": ["ok"], "additionalProperties": false],
                    maxTokens: 2_000))
                testState = "Connected: \(r.model.isEmpty ? provider.displayName : r.model)"
            } catch {
                testState = error.localizedDescription
            }
            testing = false
        }
    }
}
