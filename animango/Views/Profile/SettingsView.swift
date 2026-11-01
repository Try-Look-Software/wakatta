import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var showResetConfirmation = false
    @State private var llmConfig: LLMConfiguration?
    @State private var selectedProvider: LLMProvider = .apple
    @State private var apiKey: String = ""
    @State private var selectedModel: String = "default"
    @State private var showAPIKey = false
    @State private var testResult: String?
    @State private var isTesting = false

    var body: some View {
        List {
            llmSection

            Section("Audio") {
                HStack {
                    Image(systemName: "speaker.wave.2")
                    Text("TTS Language")
                    Spacer()
                    Text("Japanese (ja-JP)")
                        .foregroundStyle(.secondary)
                }
            }

            Section("Data") {
                Button {
                    SampleData.loadIfNeeded(modelContext: modelContext)
                } label: {
                    Label("Reload Sample Data", systemImage: "arrow.clockwise")
                }

                Button(role: .destructive) {
                    showResetConfirmation = true
                } label: {
                    Label("Reset All Progress", systemImage: "trash")
                }
            }

            // The pipeline monitor can trigger backend jobs, so keep it out of
            // App Store and TestFlight (Release) builds.
            #if DEBUG
            Section("Server") {
                NavigationLink {
                    PipelineMonitorView()
                } label: {
                    Label("Pipeline Monitor", systemImage: "server.rack")
                }
            }
            #endif

            Section("About") {
                HStack {
                    Text("Version")
                    Spacer()
                    Text("1.0.0")
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Text("App")
                    Spacer()
                    Text("Wakatta")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Settings")
        .task {
            loadLLMConfig()
        }
        .confirmationDialog(
            "Reset All Progress",
            isPresented: $showResetConfirmation,
            titleVisibility: .visible
        ) {
            Button("Reset", role: .destructive) {
                resetProgress()
            }
        } message: {
            Text("This will delete all your study progress. Your library will not be affected.")
        }
    }

    // MARK: - LLM Configuration Section

    @ViewBuilder
    private var llmSection: some View {
        Section {
            Picker("Provider", selection: $selectedProvider) {
                ForEach(LLMProvider.allCases) { provider in
                    Label(provider.displayName, systemImage: provider.iconName)
                        .tag(provider)
                }
            }
            .onChange(of: selectedProvider) { _, newProvider in
                selectedModel = newProvider.defaultModel
                if !newProvider.requiresAPIKey {
                    apiKey = ""
                }
                saveLLMConfig()
            }

            if selectedProvider.requiresAPIKey {
                VStack(alignment: .leading, spacing: 8) {
                    Text("API Key")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    HStack {
                        if showAPIKey {
                            TextField("Enter your API key", text: $apiKey)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .font(.system(.body, design: .monospaced))
                        } else {
                            SecureField("Enter your API key", text: $apiKey)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                        }

                        Button {
                            showAPIKey.toggle()
                        } label: {
                            Image(systemName: showAPIKey ? "eye.slash" : "eye")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .onChange(of: apiKey) { _, _ in
                    saveLLMConfig()
                    testResult = nil
                }
            }

            if selectedProvider.availableModels.count > 1 {
                Picker("Model", selection: $selectedModel) {
                    ForEach(selectedProvider.availableModels, id: \.self) { model in
                        Text(model).tag(model)
                    }
                }
                .onChange(of: selectedModel) { _, _ in
                    saveLLMConfig()
                }
            }

            if selectedProvider.requiresAPIKey {
                Button {
                    Task { await testConnection() }
                } label: {
                    HStack {
                        Label("Test Connection", systemImage: "network")
                        Spacer()
                        if isTesting {
                            ProgressView()
                        }
                    }
                }
                .disabled(apiKey.isEmpty || isTesting)

                if let result = testResult {
                    HStack {
                        Image(systemName: result.starts(with: "Connected") ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundStyle(result.starts(with: "Connected") ? .green : .red)
                        Text(result)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        } header: {
            Text("AI Provider")
        } footer: {
            switch selectedProvider {
            case .apple:
                Text("Uses on-device Apple Intelligence. No API key required, but requires a compatible device.")
            case .anthropic:
                Text("Uses Claude by Anthropic. Get your API key at console.anthropic.com.")
            case .openAI:
                Text("Uses ChatGPT by OpenAI. Get your API key at platform.openai.com.")
            case .gemini:
                Text("Uses Gemini by Google. Get your API key at aistudio.google.com.")
            }
        }
    }

    // MARK: - LLM Config Management

    private func loadLLMConfig() {
        let configs = (try? modelContext.fetch(FetchDescriptor<LLMConfiguration>())) ?? []
        if let config = configs.first {
            llmConfig = config
            selectedProvider = config.provider
            apiKey = config.apiKey
            selectedModel = config.selectedModel
        } else {
            let config = LLMConfiguration()
            modelContext.insert(config)
            try? modelContext.save()
            llmConfig = config
        }
    }

    private func saveLLMConfig() {
        if let config = llmConfig {
            config.provider = selectedProvider
            config.apiKey = apiKey
            config.selectedModel = selectedModel
        } else {
            let config = LLMConfiguration(
                provider: selectedProvider,
                apiKey: apiKey,
                selectedModel: selectedModel
            )
            modelContext.insert(config)
            llmConfig = config
        }
        try? modelContext.save()
    }

    private func testConnection() async {
        isTesting = true
        testResult = nil

        let provider: any LLMServiceProvider
        switch selectedProvider {
        case .anthropic:
            provider = AnthropicProvider(apiKey: apiKey, model: selectedModel)
        case .openAI:
            provider = OpenAIProvider(apiKey: apiKey, model: selectedModel)
        case .gemini:
            provider = GeminiProvider(apiKey: apiKey, model: selectedModel)
        case .apple:
            isTesting = false
            return
        }

        do {
            let response = try await provider.chat(messages: [
                LLMMessage(role: .system, content: "You are a test assistant. Respond with only: OK"),
                LLMMessage(role: .user, content: "Test")
            ])
            testResult = response.isEmpty ? "Error: Empty response" : "Connected successfully"
        } catch let error as LLMServiceError {
            testResult = error.localizedDescription
        } catch {
            testResult = "Error: \(error.localizedDescription)"
        }

        isTesting = false
    }

    private func resetProgress() {
        do {
            try modelContext.delete(model: UserProgress.self)
            try modelContext.save()
        } catch {
            // Handle error silently
        }
    }
}

#Preview {
    NavigationStack {
        SettingsView()
    }
    .modelContainer(for: [UserProgress.self, LLMConfiguration.self], inMemory: true)
}
