import Foundation
import Observation

enum ProviderKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case off, apple, ollama, openai, anthropic

    var id: String { rawValue }

    var title: String {
        switch self {
        case .off: "Off"
        case .apple: "Apple on-device"
        case .ollama: "Ollama (on this Mac)"
        case .openai: "OpenAI-compatible"
        case .anthropic: "Anthropic"
        }
    }

    /// Sends text off the Mac.
    var isCloud: Bool { self == .openai || self == .anthropic }
}

enum AIFeature: String, Codable, CaseIterable, Identifiable, Sendable {
    case explain, recap, reflection, brief, notebook

    var id: String { rawValue }

    var title: String {
        switch self {
        case .explain: "Explain & Ask"
        case .recap: "“Previously” recaps"
        case .reflection: "Reflection questions"
        case .brief: "The Brief"
        case .notebook: "Ask your notebook"
        }
    }
}

/// Provider choices and non-secret configuration. Keys are in the Keychain.
struct AISettings: Codable, Equatable, Sendable {
    var defaultProvider: ProviderKind = AppleOnDeviceProvider.isSupportedOS ? .apple : .off
    /// Per-feature override; missing means "same as default".
    var overrides: [String: ProviderKind] = [:]
    var ollamaURL = "http://localhost:11434"
    var ollamaModel = ""
    var openaiURL = "https://api.openai.com/v1"
    var openaiModel = ""
    var anthropicModel = ""

    private static let key = "FolioAISettings"

    static func load() -> AISettings {
        guard let data = UserDefaults.standard.data(forKey: key), let s = try? JSONDecoder().decode(AISettings.self, from: data) else { return AISettings() }
        return s
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) { UserDefaults.standard.set(data, forKey: Self.key) }
    }

    func provider(for feature: AIFeature) -> ProviderKind { overrides[feature.rawValue] ?? defaultProvider }
}

/// Builds providers from settings. Every AI call in the app starts here.
@MainActor @Observable
final class AIService {
    var settings: AISettings { didSet { settings.save() } }
    /// Bumps when a key changes so views re-evaluate availability.
    private(set) var keysVersion = 0

    init() { settings = AISettings.load() }

    static let openAIKeyAccount = "openai"
    static let anthropicKeyAccount = "anthropic"

    func key(_ account: String) -> String { Keychain.get(account) ?? "" }

    func setKey(_ value: String, for account: String) {
        Keychain.set(value.trimmingCharacters(in: .whitespacesAndNewlines), for: account)
        keysVersion += 1
    }

    func isEnabled(_ feature: AIFeature) -> Bool { settings.provider(for: feature) != .off }

    func provider(for feature: AIFeature) -> (any AIProvider)? {
        provider(kind: settings.provider(for: feature))
    }

    func provider(kind: ProviderKind) -> (any AIProvider)? {
        switch kind {
        case .off: return nil
        case .apple: return AppleOnDeviceProvider()
        case .ollama:
            guard let url = URL(string: settings.ollamaURL), !settings.ollamaModel.isEmpty else { return nil }
            return OllamaProvider(baseURL: url, model: settings.ollamaModel)
        case .openai:
            guard let url = URL(string: settings.openaiURL), !settings.openaiModel.isEmpty else { return nil }
            return OpenAICompatibleProvider(baseURL: url, apiKey: key(Self.openAIKeyAccount), model: settings.openaiModel)
        case .anthropic:
            let k = key(Self.anthropicKeyAccount)
            guard !k.isEmpty, !settings.anthropicModel.isEmpty else { return nil }
            return AnthropicProvider(apiKey: k, model: settings.anthropicModel)
        }
    }

    /// Provider for a feature only if it can actually run now.
    func availableProvider(for feature: AIFeature) async -> (any AIProvider)? {
        guard let p = provider(for: feature), await p.isAvailable else { return nil }
        return p
    }
}
