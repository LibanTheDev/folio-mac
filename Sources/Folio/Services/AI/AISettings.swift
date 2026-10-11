import Foundation
import SwiftUI

/// User-controlled AI configuration. External requests are opt-in, and each kind of personal
/// data that may be sent has its own consent switch.
@MainActor
final class AISettings: ObservableObject {
    static let shared = AISettings()

    enum ProviderKind: String, CaseIterable, Identifiable {
        case anthropic, openAICompatible
        var id: String { rawValue }
        var title: String { self == .anthropic ? "Anthropic (Claude)" : "OpenAI-compatible (Ollama, LM Studio…)" }
    }

    @AppStorage("ai.enabled") var enabled = false { willSet { objectWillChange.send() } }
    @AppStorage("ai.provider") var provider = ProviderKind.anthropic { willSet { objectWillChange.send() } }
    @AppStorage("ai.anthropicModel") var anthropicModel = "claude-opus-5-5" { willSet { objectWillChange.send() } }
    @AppStorage("ai.compatibleBaseURL") var compatibleBaseURL = "http://localhost:11434/v1" { willSet { objectWillChange.send() } }
    @AppStorage("ai.compatibleModel") var compatibleModel = "llama3.1" { willSet { objectWillChange.send() } }
    /// May book titles, authors, ratings and shelves be included in prompts?
    @AppStorage("ai.shareLibrary") var shareLibrary = true { willSet { objectWillChange.send() } }
    /// May notes, highlights and reflections be included in prompts?
    @AppStorage("ai.shareNotes") var shareNotes = false { willSet { objectWillChange.send() } }

    private var keyAccount: String { provider == .anthropic ? "anthropic" : "compatible" }

    var hasKey: Bool { Keychain.get(account: keyAccount)?.isEmpty == false }

    func saveKey(_ key: String) throws {
        try Keychain.set(key.trimmingCharacters(in: .whitespacesAndNewlines), account: keyAccount)
        objectWillChange.send()
    }

    func removeKey() {
        Keychain.delete(account: keyAccount)
        objectWillChange.send()
    }

    /// The configured provider, or an error explaining what's missing.
    func makeProvider() throws -> AIProvider {
        guard enabled else { throw AIError.disabled }
        switch provider {
        case .anthropic:
            guard let key = Keychain.get(account: "anthropic"), !key.isEmpty else {
                throw AIError.notConfigured("add your Anthropic API key in Settings → AI.")
            }
            return AnthropicProvider(apiKey: key, model: anthropicModel)
        case .openAICompatible:
            guard let url = URL(string: compatibleBaseURL), url.scheme != nil else {
                throw AIError.notConfigured("the server URL is invalid.")
            }
            return OpenAICompatibleProvider(baseURL: url, apiKey: Keychain.get(account: "compatible"), model: compatibleModel)
        }
    }

    /// A short description of what leaves the Mac, shown next to AI actions.
    var dataDisclosure: String {
        var parts: [String] = ["your question"]
        if shareLibrary { parts.append("book titles, authors, ratings and shelves") }
        if shareNotes { parts.append("relevant notes and highlights") }
        let destination = provider == .anthropic ? "Anthropic" : (URL(string: compatibleBaseURL)?.host ?? "your server")
        return "Sends \(parts.joined(separator: ", ")) to \(destination)."
    }
}
