import AppKit
import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettings().tabItem { Label("General", systemImage: "gearshape") }
            AISettingsView().tabItem { Label("AI", systemImage: "sparkles") }
        }
        .frame(width: 580, height: 640)
        .tint(DS.accent)
    }
}

private struct GeneralSettings: View {
    @EnvironmentObject var library: Library
    @AppStorage("appearance") private var appearance = Appearance.system

    var body: some View {
        Form {
            Picker("Appearance", selection: $appearance) {
                ForEach(Appearance.allCases) { Text($0.title).tag($0) }
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
                Text("Folio keeps a daily backup (last 14 days) and a copy before every migration or restore. Everything stays on this Mac.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding(.vertical, 8)
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
