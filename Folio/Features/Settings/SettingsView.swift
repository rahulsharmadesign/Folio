import SwiftUI

/// Folio › Settings (⌘,). Not in the designs: a standard macOS settings window, kept plain.
struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettings().tabItem { Label("General", systemImage: "gearshape") }
            AISettingsPane().tabItem { Label("AI", systemImage: "text.bubble") }
        }
        .frame(width: 560)
    }
}

private struct GeneralSettings: View {
    @Environment(AppState.self) private var app

    var body: some View {
        @Bindable var app = app
        Form {
            Toggle("Open Folio at login, so editions arrive with the window closed", isOn: $app.prefs.openAtLogin)
            Toggle("Quiet arrival (menu bar only; no banner or sound)", isOn: Binding(get: { app.prefs.quietArrival }, set: { quiet in
                app.prefs.quietArrival = quiet
                if !quiet { app.scheduler.requestNotificationPermission() }
            }))
            Toggle("Editions never pile up", isOn: $app.prefs.neverPileUp)
            Section {
                Button("Show Welcome Again") {
                    app.prefs.onboarded = false
                    app.route = .onboarding
                }
            }
        }
        .formStyle(.grouped)
        .padding(.vertical, 8)
    }
}

private struct AISettingsPane: View {
    @Environment(AppState.self) private var app
    @State private var openAIKey = ""
    @State private var anthropicKey = ""
    @State private var ollamaModels: [String] = []
    @State private var openAIModels: [String] = []
    @State private var anthropicModels: [String] = []
    @State private var status: [ProviderKind: String] = [:]
    @State private var testResult = ""

    private var ai: AIService { app.ai }

    var body: some View {
        @Bindable var ai = app.ai
        Form {
            Section {
                Picker("Default provider", selection: $ai.settings.defaultProvider) {
                    ForEach(ProviderKind.allCases) { kind in
                        Text(kind.title).tag(kind).disabled(kind == .apple && !AppleOnDeviceProvider.isSupportedOS)
                    }
                }
                ForEach(AIFeature.allCases) { feature in
                    Picker(feature.title, selection: Binding(
                        get: { ai.settings.overrides[feature.rawValue] },
                        set: { ai.settings.overrides[feature.rawValue] = $0; app.scheduler.retryBriefs() })) {
                        Text("Same as default").tag(ProviderKind?.none)
                        ForEach(ProviderKind.allCases) { kind in Text(kind.title).tag(ProviderKind?.some(kind)) }
                    }
                }
            } footer: {
                Text(privacyNote).font(.callout).foregroundStyle(.secondary)
            }

            Section("Apple on-device") {
                Text(AppleOnDeviceProvider.isSupportedOS
                     ? "Private, free and offline. Needs Apple silicon with Apple Intelligence turned on."
                     : "Needs macOS 26 or later.")
                    .foregroundStyle(.secondary)
            }

            Section("Ollama") {
                TextField("Server", text: $ai.settings.ollamaURL)
                modelPicker(selection: $ai.settings.ollamaModel, models: ollamaModels, kind: .ollama) {
                    guard let url = URL(string: ai.settings.ollamaURL) else { return }
                    ollamaModels = try await OllamaProvider.models(baseURL: url)
                }
            }

            Section("OpenAI-compatible") {
                TextField("Base URL", text: $ai.settings.openaiURL)
                SecureField("API key (stored in the Keychain)", text: $openAIKey)
                    .onSubmit { ai.setKey(openAIKey, for: AIService.openAIKeyAccount) }
                modelPicker(selection: $ai.settings.openaiModel, models: openAIModels, kind: .openai) {
                    ai.setKey(openAIKey, for: AIService.openAIKeyAccount)
                    guard let url = URL(string: ai.settings.openaiURL) else { return }
                    openAIModels = try await OpenAICompatibleProvider.models(baseURL: url, apiKey: openAIKey)
                }
            }

            Section("Anthropic") {
                SecureField("API key (stored in the Keychain)", text: $anthropicKey)
                    .onSubmit { ai.setKey(anthropicKey, for: AIService.anthropicKeyAccount) }
                modelPicker(selection: $ai.settings.anthropicModel, models: anthropicModels, kind: .anthropic) {
                    ai.setKey(anthropicKey, for: AIService.anthropicKeyAccount)
                    anthropicModels = try await AnthropicProvider.models(apiKey: anthropicKey)
                    if ai.settings.anthropicModel.isEmpty {
                        ai.settings.anthropicModel = anthropicModels.contains(AnthropicProvider.preferredModel)
                            ? AnthropicProvider.preferredModel : anthropicModels.first ?? ""
                    }
                }
            }

            Section {
                HStack {
                    Button("Test Default Provider") { Task { await test() } }
                    Text(testResult).foregroundStyle(.secondary).lineLimit(2)
                }
            }
        }
        .formStyle(.grouped)
        .frame(minHeight: 560)
        .onAppear {
            openAIKey = ai.key(AIService.openAIKeyAccount)
            anthropicKey = ai.key(AIService.anthropicKeyAccount)
        }
        .onDisappear {
            ai.setKey(openAIKey, for: AIService.openAIKeyAccount)
            ai.setKey(anthropicKey, for: AIService.anthropicKeyAccount)
        }
    }

    private var privacyNote: String {
        let cloud = AIFeature.allCases.filter { ai.settings.provider(for: $0).isCloud }
        let base = "With AI off, Folio still works: there are simply no Briefs, recaps or Explain. Apple on-device and Ollama keep your text on this Mac."
        guard !cloud.isEmpty else { return base }
        return base + " With your current choices, the text you read is sent to the cloud provider for: " + cloud.map(\.title).joined(separator: ", ") + "."
    }

    private func modelPicker(selection: Binding<String>, models: [String], kind: ProviderKind, load: @escaping () async throws -> Void) -> some View {
        HStack {
            Picker("Model", selection: selection) {
                if selection.wrappedValue.isEmpty { Text("Choose…").tag("") }
                ForEach(Array(Set(models + [selection.wrappedValue]).filter { !$0.isEmpty }).sorted(), id: \.self) { Text($0).tag($0) }
            }
            Button("Fetch Models") {
                Task {
                    status[kind] = "Loading…"
                    do {
                        try await load()
                        status[kind] = nil
                    } catch {
                        status[kind] = (error as? LocalizedError)?.errorDescription ?? "Couldn’t reach it."
                    }
                }
            }
            if let s = status[kind] { Text(s).foregroundStyle(.secondary).lineLimit(1) }
        }
    }

    private func test() async {
        ai.setKey(openAIKey, for: AIService.openAIKeyAccount)
        ai.setKey(anthropicKey, for: AIService.anthropicKeyAccount)
        testResult = "Asking…"
        guard let provider = ai.provider(kind: ai.settings.defaultProvider), await provider.isAvailable else {
            testResult = ai.settings.defaultProvider == .off ? "AI is off." : "Not available — check the settings above."
            return
        }
        do {
            testResult = try await provider.complete(AIRequest(system: "Reply in five words or fewer.", prompt: "Say hello to a reader.", maxTokens: 2000))
        } catch {
            testResult = (error as? LocalizedError)?.errorDescription ?? "Failed."
        }
    }
}
