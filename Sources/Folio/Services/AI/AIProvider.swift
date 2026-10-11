import Foundation

struct AIRequest {
    var system: String
    var user: String
    /// JSON Schema for the response object. Providers must return JSON matching it.
    var schema: [String: Any]
    var maxTokens = 16_000
}

struct AIResponse {
    var json: Data
    var model: String
}

enum AIError: LocalizedError {
    case disabled
    case notConfigured(String)
    case http(Int, String)
    case refused(String?)
    case truncated
    case invalidJSON
    case network(String)

    var errorDescription: String? {
        switch self {
        case .disabled: "AI features are turned off. Enable them in Settings → AI."
        case .notConfigured(let what): "AI isn't set up: \(what)"
        case .http(let code, let message): "The AI provider returned an error (\(code)): \(message)"
        case .refused(let category): "The model declined this request" + (category.map { " (\($0))" } ?? "") + "."
        case .truncated: "The AI response was cut off. Try a narrower question."
        case .invalidJSON: "The AI response couldn't be read. Try again."
        case .network(let m): "Couldn't reach the AI provider: \(m)"
        }
    }
}

/// Anything that can turn a prompt into schema-conforming JSON.
protocol AIProvider {
    var displayName: String { get }
    func complete(_ request: AIRequest) async throws -> AIResponse
}

// MARK: - Anthropic (Claude)

/// Claude via the Messages API over HTTPS (Swift has no official Anthropic SDK).
struct AnthropicProvider: AIProvider {
    var apiKey: String
    var model: String = "claude-opus-5-5"
    var effort: String = "medium"
    var session: URLSession = .shared

    var displayName: String { "Claude (\(model))" }

    func body(for request: AIRequest) -> [String: Any] {
        [
            "model": model,
            "max_tokens": request.maxTokens,
            "system": request.system,
            "messages": [["role": "user", "content": request.user]],
            "output_config": [
                "effort": effort,
                "format": ["type": "json_schema", "schema": request.schema],
            ],
            // On a safety decline, let the API re-run the request on an appropriate fallback model.
            "fallbacks": "default",
        ]
    }

    func complete(_ request: AIRequest) async throws -> AIResponse {
        var req = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        req.httpMethod = "POST"
        req.timeoutInterval = 300
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        req.setValue("server-side-fallback-2026-07-01", forHTTPHeaderField: "anthropic-beta")
        req.httpBody = try JSONSerialization.data(withJSONObject: body(for: request))

        let (data, response): (Data, URLResponse)
        do { (data, response) = try await session.data(for: req) } catch { throw AIError.network(error.localizedDescription) }
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        guard code == 200, let obj else {
            let message = ((obj?["error"] as? [String: Any])?["message"] as? String) ?? String(decoding: data.prefix(300), as: UTF8.self)
            throw AIError.http(code, message)
        }
        return try Self.parse(obj)
    }

    /// Extracts the JSON text from a Messages API response, checking stop reasons first.
    static func parse(_ obj: [String: Any]) throws -> AIResponse {
        let stop = obj["stop_reason"] as? String
        if stop == "refusal" {
            throw AIError.refused((obj["stop_details"] as? [String: Any])?["category"] as? String)
        }
        if stop == "max_tokens" { throw AIError.truncated }
        let blocks = obj["content"] as? [[String: Any]] ?? []
        let text = blocks.filter { $0["type"] as? String == "text" }.compactMap { $0["text"] as? String }.joined()
        guard let json = JSONExtraction.object(in: text) else { throw AIError.invalidJSON }
        return AIResponse(json: json, model: obj["model"] as? String ?? "")
    }
}

// MARK: - OpenAI-compatible (local Ollama / LM Studio, or hosted)

struct OpenAICompatibleProvider: AIProvider {
    var baseURL: URL
    var apiKey: String?
    var model: String
    var session: URLSession = .shared

    var displayName: String { "\(model) at \(baseURL.host ?? baseURL.absoluteString)" }

    func complete(_ request: AIRequest) async throws -> AIResponse {
        var req = URLRequest(url: baseURL.appendingPathComponent("chat/completions"))
        req.httpMethod = "POST"
        req.timeoutInterval = 600
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let apiKey, !apiKey.isEmpty { req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization") }
        let body: [String: Any] = [
            "model": model,
            "max_tokens": request.maxTokens,
            "messages": [
                ["role": "system", "content": request.system + "\n\nRespond with a single JSON object only."],
                ["role": "user", "content": request.user],
            ],
            "response_format": ["type": "json_schema",
                                "json_schema": ["name": "folio_response", "schema": request.schema, "strict": true]],
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response): (Data, URLResponse)
        do { (data, response) = try await session.data(for: req) } catch { throw AIError.network(error.localizedDescription) }
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard code == 200,
              let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let choice = (obj["choices"] as? [[String: Any]])?.first,
              let message = choice["message"] as? [String: Any] else {
            throw AIError.http(code, String(decoding: data.prefix(300), as: UTF8.self))
        }
        if choice["finish_reason"] as? String == "length" { throw AIError.truncated }
        guard let text = message["content"] as? String, let json = JSONExtraction.object(in: text) else { throw AIError.invalidJSON }
        return AIResponse(json: json, model: obj["model"] as? String ?? model)
    }
}

enum JSONExtraction {
    /// The first complete top-level JSON object in `text` (tolerates code fences or stray prose).
    static func object(in text: String) -> Data? {
        let chars = Array(text)
        guard let start = chars.firstIndex(of: "{") else { return nil }
        var depth = 0, inString = false, escaped = false
        for i in start..<chars.count {
            let c = chars[i]
            if inString {
                if escaped { escaped = false } else if c == "\\" { escaped = true } else if c == "\"" { inString = false }
                continue
            }
            if c == "\"" { inString = true } else if c == "{" { depth += 1 } else if c == "}" {
                depth -= 1
                if depth == 0 {
                    let data = Data(String(chars[start...i]).utf8)
                    return (try? JSONSerialization.jsonObject(with: data)) != nil ? data : nil
                }
            }
        }
        return nil
    }
}
