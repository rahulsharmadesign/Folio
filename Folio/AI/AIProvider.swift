import Foundation

/// One message in a request.
struct AIMessage: Codable, Sendable, Hashable {
    enum Role: String, Codable, Sendable { case user, assistant }
    var role: Role
    var content: String
}

struct AIRequest: Sendable {
    var system: String
    var messages: [AIMessage]
    var maxTokens: Int = 16000

    init(system: String, prompt: String, maxTokens: Int = 16000) {
        self.system = system
        messages = [AIMessage(role: .user, content: prompt)]
        self.maxTokens = maxTokens
    }
}

enum AIError: LocalizedError {
    case unavailable
    case badResponse(Int, String)
    case emptyResponse
    case missingKey

    var errorDescription: String? {
        switch self {
        case .unavailable: "The AI provider isn’t available right now."
        case .badResponse(let code, let message): "The AI provider returned an error (\(code)). \(message)"
        case .emptyResponse: "The AI provider returned nothing."
        case .missingKey: "Add an API key in Settings › AI."
        }
    }
}

/// Every AI feature goes through this (SPEC › AI layer). Views never call a vendor directly.
protocol AIProvider: Sendable {
    var id: String { get }
    var isAvailable: Bool { get async }
    func complete(_ req: AIRequest) async throws -> String
    func stream(_ req: AIRequest) -> AsyncThrowingStream<String, Error>
}

extension AIProvider {
    /// Default: collect the stream.
    func complete(_ req: AIRequest) async throws -> String {
        var text = ""
        for try await chunk in stream(req) { text += chunk }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { throw AIError.emptyResponse }
        return trimmed
    }
}

// MARK: - Shared HTTP helpers

enum AIHTTP {
    static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 120
        config.timeoutIntervalForResource = 600
        return URLSession(configuration: config)
    }()

    static func jsonRequest(_ url: URL, method: String = "POST", body: [String: Any]? = nil, headers: [String: String] = [:]) throws -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        for (k, v) in headers { request.setValue(v, forHTTPHeaderField: k) }
        if let body { request.httpBody = try JSONSerialization.data(withJSONObject: body) }
        return request
    }

    /// Checks the status; on failure reads a short error message from the body.
    static func check(_ response: URLResponse, bytes: URLSession.AsyncBytes) async throws {
        guard let http = response as? HTTPURLResponse else { throw AIError.unavailable }
        guard (200..<300).contains(http.statusCode) else {
            var body = ""
            for try await line in bytes.lines { body += line; if body.count > 600 { break } }
            throw AIError.badResponse(http.statusCode, errorMessage(body))
        }
    }

    static func errorMessage(_ body: String) -> String {
        guard let data = body.data(using: .utf8), let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return String(body.prefix(200))
        }
        if let error = json["error"] as? [String: Any], let message = error["message"] as? String { return message }
        if let error = json["error"] as? String { return error }
        return String(body.prefix(200))
    }

    static func getJSON(_ url: URL, headers: [String: String] = [:]) async throws -> Any {
        let request = try jsonRequest(url, method: "GET", headers: headers)
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw AIError.badResponse((response as? HTTPURLResponse)?.statusCode ?? 0, errorMessage(String(data: data, encoding: .utf8) ?? ""))
        }
        return try JSONSerialization.jsonObject(with: data)
    }

    /// Streams `data:` payloads of a server-sent-event response.
    static func sse(_ request: URLRequest, onData: @escaping @Sendable (String) throws -> String?) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let (bytes, response) = try await session.bytes(for: request)
                    try await check(response, bytes: bytes)
                    for try await line in bytes.lines {
                        guard line.hasPrefix("data:") else { continue }
                        let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
                        if payload == "[DONE]" { break }
                        if let text = try onData(payload), !text.isEmpty { continuation.yield(text) }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    static func json(_ payload: String) -> [String: Any]? {
        payload.data(using: .utf8).flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
    }
}
