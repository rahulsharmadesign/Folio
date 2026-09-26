import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

// MARK: - Apple on-device

/// Apple Intelligence's on-device model (macOS 26+, Apple silicon, Apple Intelligence on). Private, free, offline.
struct AppleOnDeviceProvider: AIProvider {
    let id = "apple"

    var isAvailable: Bool {
        get async {
            #if canImport(FoundationModels)
            if #available(macOS 26, *) { return SystemLanguageModel.default.isAvailable }
            #endif
            return false
        }
    }

    static var isSupportedOS: Bool {
        if #available(macOS 26, *) { return true }
        return false
    }

    func stream(_ req: AIRequest) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                #if canImport(FoundationModels)
                if #available(macOS 26, *) {
                    do {
                        let session = LanguageModelSession(instructions: req.system)
                        let prompt = req.messages.map(\.content).joined(separator: "\n\n")
                        var sent = ""
                        // Snapshots are cumulative; yield only what's new.
                        for try await snapshot in session.streamResponse(to: prompt) {
                            let text = snapshot.content
                            if text.hasPrefix(sent) {
                                continuation.yield(String(text.dropFirst(sent.count)))
                            } else {
                                continuation.yield(text)
                            }
                            sent = text
                        }
                        continuation.finish()
                    } catch {
                        continuation.finish(throwing: error)
                    }
                    return
                }
                #endif
                continuation.finish(throwing: AIError.unavailable)
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

// MARK: - Ollama

/// Ollama on this Mac (`http://localhost:11434`): models from /api/tags, chat via /api/chat.
struct OllamaProvider: AIProvider {
    let id = "ollama"
    var baseURL: URL
    var model: String

    var isAvailable: Bool {
        get async {
            guard !model.isEmpty else { return false }
            return (try? await Self.models(baseURL: baseURL)) != nil
        }
    }

    static func models(baseURL: URL) async throws -> [String] {
        let json = try await AIHTTP.getJSON(baseURL.appendingPathComponent("api/tags"))
        return ((json as? [String: Any])?["models"] as? [[String: Any]] ?? []).compactMap { $0["name"] as? String }.sorted()
    }

    func stream(_ req: AIRequest) -> AsyncThrowingStream<String, Error> {
        let messages = [["role": "system", "content": req.system]] + req.messages.map { ["role": $0.role.rawValue, "content": $0.content] }
        let body: [String: Any] = ["model": model, "messages": messages, "stream": true]
        guard let request = try? AIHTTP.jsonRequest(baseURL.appendingPathComponent("api/chat"), body: body) else {
            return AsyncThrowingStream { $0.finish(throwing: AIError.unavailable) }
        }
        // Ollama streams newline-delimited JSON, not SSE.
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let (bytes, response) = try await AIHTTP.session.bytes(for: request)
                    try await AIHTTP.check(response, bytes: bytes)
                    for try await line in bytes.lines {
                        guard let json = AIHTTP.json(line) else { continue }
                        if let error = json["error"] as? String { throw AIError.badResponse(0, error) }
                        if let text = (json["message"] as? [String: Any])?["content"] as? String, !text.isEmpty { continuation.yield(text) }
                        if json["done"] as? Bool == true { break }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

// MARK: - OpenAI-compatible

/// Any OpenAI-compatible endpoint: LM Studio (`localhost:1234/v1`), Groq, OpenRouter, OpenAI…
struct OpenAICompatibleProvider: AIProvider {
    let id = "openai"
    var baseURL: URL
    var apiKey: String
    var model: String

    var isAvailable: Bool { get async { !model.isEmpty } }

    private static func headers(_ key: String) -> [String: String] {
        key.isEmpty ? [:] : ["Authorization": "Bearer \(key)"]
    }

    static func models(baseURL: URL, apiKey: String) async throws -> [String] {
        let json = try await AIHTTP.getJSON(baseURL.appendingPathComponent("models"), headers: headers(apiKey))
        return ((json as? [String: Any])?["data"] as? [[String: Any]] ?? []).compactMap { $0["id"] as? String }.sorted()
    }

    func stream(_ req: AIRequest) -> AsyncThrowingStream<String, Error> {
        let messages = [["role": "system", "content": req.system]] + req.messages.map { ["role": $0.role.rawValue, "content": $0.content] }
        let body: [String: Any] = ["model": model, "messages": messages, "stream": true, "max_tokens": req.maxTokens]
        guard let request = try? AIHTTP.jsonRequest(baseURL.appendingPathComponent("chat/completions"), body: body, headers: Self.headers(apiKey)) else {
            return AsyncThrowingStream { $0.finish(throwing: AIError.unavailable) }
        }
        return AIHTTP.sse(request) { payload in
            guard let json = AIHTTP.json(payload) else { return nil }
            let choice = (json["choices"] as? [[String: Any]])?.first
            return (choice?["delta"] as? [String: Any])?["content"] as? String
        }
    }
}

// MARK: - Anthropic

/// The Claude Messages API with the user's own key (raw HTTPS; there's no official Swift SDK).
struct AnthropicProvider: AIProvider {
    let id = "anthropic"
    var apiKey: String
    var model: String

    static let baseURL = URL(string: "https://api.anthropic.com/v1/")!
    /// Preselected when the key can use it; the list itself is always fetched.
    static let preferredModel = "claude-opus-5"

    var isAvailable: Bool { get async { !apiKey.isEmpty && !model.isEmpty } }

    private static func headers(_ key: String, fallbacks: Bool = false) -> [String: String] {
        var h = ["x-api-key": key, "anthropic-version": "2023-06-01"]
        if fallbacks { h["anthropic-beta"] = "server-side-fallback-2026-07-01" }
        return h
    }

    static func models(apiKey: String) async throws -> [String] {
        guard !apiKey.isEmpty else { throw AIError.missingKey }
        let json = try await AIHTTP.getJSON(baseURL.appendingPathComponent("models"), headers: headers(apiKey))
        return ((json as? [String: Any])?["data"] as? [[String: Any]] ?? []).compactMap { $0["id"] as? String }
    }

    func stream(_ req: AIRequest) -> AsyncThrowingStream<String, Error> {
        guard !apiKey.isEmpty else { return AsyncThrowingStream { $0.finish(throwing: AIError.missingKey) } }
        // Opus 5 / Fable: route policy declines to a fallback model instead of stopping.
        let fallbacks = model.hasPrefix("claude-opus-5") || model.hasPrefix("claude-fable-5")
        var body: [String: Any] = [
            "model": model,
            "max_tokens": req.maxTokens,
            "system": req.system,
            "messages": req.messages.map { ["role": $0.role.rawValue, "content": $0.content] },
            "stream": true,
        ]
        if fallbacks { body["fallbacks"] = "default" }
        guard let request = try? AIHTTP.jsonRequest(Self.baseURL.appendingPathComponent("messages"), body: body,
                                                    headers: Self.headers(apiKey, fallbacks: fallbacks)) else {
            return AsyncThrowingStream { $0.finish(throwing: AIError.unavailable) }
        }
        return AIHTTP.sse(request) { payload in
            guard let json = AIHTTP.json(payload) else { return nil }
            switch json["type"] as? String {
            case "content_block_delta":
                let delta = json["delta"] as? [String: Any]
                return delta?["type"] as? String == "text_delta" ? delta?["text"] as? String : nil
            case "error":
                let message = (json["error"] as? [String: Any])?["message"] as? String ?? "Stream error"
                throw AIError.badResponse(0, message)
            default:
                return nil
            }
        }
    }
}
