import SwiftUI
import AppKit

struct MLXWhisperPreset: Identifiable, Hashable {
    let modelID: String
    let displayName: String
    let qualityHint: String

    var id: String { modelID }
    var menuLabel: String { "\(displayName) — \(qualityHint)" }
}

struct OllamaSuggestedModel: Identifiable, Hashable {
    let tag: String
    let label: String
    let qualityHint: String

    var id: String { tag }
    var menuLabel: String { "\(label) — \(qualityHint)" }
}

enum SettingsTab: Hashable {
    case transcription
    case summarization
    case general
}

struct SettingsWindow: View {
    @State private var selection: SettingsTab = .transcription

    var body: some View {
        TabView(selection: $selection) {
            TranscriptionSettingsTab()
                .tabItem { Label("Transcription", systemImage: "waveform") }
                .tag(SettingsTab.transcription)
            SummarizationSettingsTab()
                .tabItem { Label("Summarization", systemImage: "sparkles") }
                .tag(SettingsTab.summarization)
            GeneralSettingsTab()
                .tabItem { Label("General", systemImage: "folder") }
                .tag(SettingsTab.general)
        }
        .frame(width: 620, height: 620)
        .onAppear { AppActivation.shared.windowDidAppear() }
        .onDisappear { AppActivation.shared.windowDidDisappear() }
    }
}

// MARK: - Transcription tab

private struct TranscriptionSettingsTab: View {
    @AppStorage(SettingsKeys.transcriptionProvider) private var transcriptionProviderRaw: String = TranscriptionProvider.apple.rawValue
    @AppStorage(SettingsKeys.mlxWhisperModel) private var mlxWhisperModel: String = AppSettings.defaultMLXWhisperModel
    @AppStorage(SettingsKeys.mlxWhisperPath) private var mlxWhisperPath: String = ""

    @State private var mlxInstallPath: URL?
    @State private var mlxCachedPresets: Set<String> = []
    @State private var mlxFFmpegInstalled = false
    @State private var mlxDownloadStatus: String?
    @State private var mlxDownloadingModel: String?

    static let mlxWhisperPresets: [MLXWhisperPreset] = [
        .init(modelID: "mlx-community/whisper-base", displayName: "Base", qualityHint: "best for realtime"),
        .init(modelID: "mlx-community/whisper-large-v3-turbo", displayName: "Large v3 Turbo", qualityHint: "balanced"),
        .init(modelID: "mlx-community/whisper-large-v3-mlx", displayName: "Large v3", qualityHint: "highest accuracy")
    ]

    var body: some View {
        Form {
            Section {
                Picker("Provider", selection: $transcriptionProviderRaw) {
                    ForEach(TranscriptionProvider.allCases) { provider in
                        Text(provider.displayName).tag(provider.rawValue)
                    }
                }
                Text("Live partials in the menu bar always use Apple SpeechAnalyzer. This setting controls the final transcript saved to the .md.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if transcriptionProviderRaw == TranscriptionProvider.mlxWhisper.rawValue {
                mlxWhisperSection
            }
        }
        .formStyle(.grouped)
        .onAppear {
            if transcriptionProviderRaw == TranscriptionProvider.mlxWhisper.rawValue {
                refreshMLXStatus()
            }
        }
        .onChange(of: transcriptionProviderRaw) { _, newValue in
            if newValue == TranscriptionProvider.mlxWhisper.rawValue {
                refreshMLXStatus()
            }
        }
        .onChange(of: mlxWhisperModel) { _, newValue in
            refreshMLXStatus()
            if !newValue.isEmpty,
               mlxInstallPath != nil,
               !mlxCachedPresets.contains(newValue),
               mlxDownloadingModel == nil {
                Task { await downloadMLXModel(newValue) }
            }
        }
        .onChange(of: mlxWhisperPath) { _, _ in refreshMLXStatus() }
    }

    @ViewBuilder
    private var mlxWhisperSection: some View {
        Section("MLX Whisper") {
            LabeledContent("Model") {
                Picker("Model", selection: $mlxWhisperModel) {
                    if !Self.mlxWhisperPresets.contains(where: { $0.modelID == mlxWhisperModel }),
                       !mlxWhisperModel.isEmpty {
                        modelRow(
                            label: "\(mlxWhisperModel) (custom)",
                            isReady: mlxCachedPresets.contains(mlxWhisperModel)
                        )
                        .tag(mlxWhisperModel)
                        Divider()
                    }
                    ForEach(Self.mlxWhisperPresets) { preset in
                        modelRow(
                            label: preset.menuLabel,
                            isReady: mlxCachedPresets.contains(preset.modelID)
                        )
                        .tag(preset.modelID)
                    }
                }
                .labelsHidden()
            }
            Text("Switching to a model that isn't cached locally starts the download automatically.")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                if let path = mlxInstallPath {
                    Label("Detected at \(path.path(percentEncoded: false))", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .lineLimit(1)
                        .truncationMode(.middle)
                } else {
                    Label("Not installed", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Spacer()
                    Button("Copy install command") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString("pip install mlx-whisper", forType: .string)
                    }
                }
            }
            if mlxInstallPath == nil {
                Text("Run this in Terminal, then click Refresh:\n  pip install mlx-whisper")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 8) {
                if mlxFFmpegInstalled {
                    Label("ffmpeg installed", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                } else {
                    Label("ffmpeg missing — brew install ffmpeg", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Spacer()
                    Button("Copy") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString("brew install ffmpeg", forType: .string)
                    }
                }
            }

            HStack(spacing: 8) {
                if mlxCachedPresets.contains(mlxWhisperModel) {
                    Label("Model cached", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                } else {
                    Label("Model not cached", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
                Spacer()
                Button {
                    Task { await downloadMLXModel(mlxWhisperModel) }
                } label: {
                    if mlxDownloadingModel != nil {
                        HStack(spacing: 4) {
                            ProgressView().controlSize(.small)
                            Text("Downloading…")
                        }
                    } else {
                        Text(mlxCachedPresets.contains(mlxWhisperModel) ? "Re-warm" : "Download model")
                    }
                }
                .disabled(mlxDownloadingModel != nil || mlxInstallPath == nil)

                Button {
                    refreshMLXStatus()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .help("Re-check installation and cache")
            }
            if let mlxDownloadStatus {
                Text(mlxDownloadStatus).font(.caption).foregroundStyle(.secondary)
            }

            DisclosureGroup("Advanced") {
                LabeledContent("mlx_whisper path") {
                    TextField("auto-detect via PATH", text: $mlxWhisperPath)
                        .textFieldStyle(.roundedBorder)
                }
                Text("Leave blank to auto-detect via $PATH. Override only if mlx_whisper lives outside your shell PATH (e.g. in a pyenv or conda environment).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func refreshMLXStatus() {
        mlxInstallPath = MLXWhisperEnvironment.detectInstallation(overridePath: mlxWhisperPath)
        var cached: Set<String> = []
        for preset in Self.mlxWhisperPresets {
            if MLXWhisperEnvironment.isModelCached(preset.modelID) {
                cached.insert(preset.modelID)
            }
        }
        if !mlxWhisperModel.isEmpty,
           !Self.mlxWhisperPresets.contains(where: { $0.modelID == mlxWhisperModel }),
           MLXWhisperEnvironment.isModelCached(mlxWhisperModel) {
            cached.insert(mlxWhisperModel)
        }
        mlxCachedPresets = cached
        mlxFFmpegInstalled = MLXWhisperEnvironment.isFFmpegInstalled()
    }

    private func downloadMLXModel(_ modelName: String) async {
        guard mlxInstallPath != nil else {
            mlxDownloadStatus = "Install mlx-whisper first."
            return
        }
        let target = modelName.isEmpty ? AppSettings.defaultMLXWhisperModel : modelName
        mlxDownloadingModel = target
        mlxDownloadStatus = "Warming up \(target)… first run may take 1–2 minutes."
        defer {
            mlxDownloadingModel = nil
            refreshMLXStatus()
        }
        do {
            try await MLXWhisperEnvironment.warmupDownload(model: target, overridePath: mlxWhisperPath)
            mlxDownloadStatus = "\(target) is ready."
        } catch {
            mlxDownloadStatus = "Failed: \(error.localizedDescription)"
        }
    }
}

// MARK: - Summarization tab

private struct SummarizationSettingsTab: View {
    @AppStorage(SettingsKeys.llmProvider) private var llmProviderRaw: String = LLMProvider.apple.rawValue
    @AppStorage(SettingsKeys.ollamaBaseURL) private var ollamaBaseURL: String = AppSettings.defaultOllamaBaseURL
    @AppStorage(SettingsKeys.ollamaModel) private var ollamaModel: String = ""
    @AppStorage(SettingsKeys.ollamaTemperature) private var ollamaTemperature: Double = AppSettings.defaultOllamaTemperature

    @State private var availableModels: [String] = []
    @State private var modelLoadStatus: String?
    @State private var isLoadingModels = false
    @State private var ollamaReachable = false
    @State private var pullingModelTag: String?
    @State private var ollamaPullStatus: String?
    @State private var ollamaPullError: String?

    static let suggestedOllamaModels: [OllamaSuggestedModel] = [
        .init(tag: "llama3.3:70b", label: "Llama 3.3 70B", qualityHint: "accuracy"),
        .init(tag: "qwen2.5:32b", label: "Qwen 2.5 32B", qualityHint: "balanced"),
        .init(tag: "llama3.1:8b", label: "Llama 3.1 8B", qualityHint: "performance")
    ]

    var body: some View {
        Form {
            Section {
                Picker("Provider", selection: $llmProviderRaw) {
                    ForEach(LLMProvider.allCases) { provider in
                        Text(provider.displayName).tag(provider.rawValue)
                    }
                }
            }

            if llmProviderRaw == LLMProvider.ollama.rawValue {
                ollamaSection
            }
        }
        .formStyle(.grouped)
        .onAppear {
            if llmProviderRaw == LLMProvider.ollama.rawValue {
                Task { await refreshModels() }
            }
        }
        .onChange(of: llmProviderRaw) { _, newValue in
            if newValue == LLMProvider.ollama.rawValue {
                Task { await refreshModels() }
            }
        }
        .onChange(of: ollamaBaseURL) { _, _ in
            if llmProviderRaw == LLMProvider.ollama.rawValue {
                Task { await refreshModels() }
            }
        }
    }

    @ViewBuilder
    private var ollamaSection: some View {
        Section("Ollama") {
            LabeledContent("Base URL") {
                TextField("http://localhost:11434", text: $ollamaBaseURL)
                    .textFieldStyle(.roundedBorder)
            }

            if ollamaReachable {
                LabeledContent("Model") {
                    HStack(spacing: 6) {
                        Picker("Model", selection: $ollamaModel) {
                            if ollamaModel.isEmpty {
                                Text("(none)").tag("")
                            }
                            if !availableModels.isEmpty {
                                Section("Installed") {
                                    ForEach(availableModels, id: \.self) { name in
                                        modelRow(label: name, isReady: true).tag(name)
                                    }
                                }
                            }
                            Section("Suggested") {
                                ForEach(suggestedOllamaModelsNotInstalled) { suggested in
                                    modelRow(label: suggested.menuLabel, isReady: false)
                                        .tag(suggested.tag)
                                }
                            }
                        }
                        .labelsHidden()

                        Button {
                            Task { await refreshModels() }
                        } label: {
                            if isLoadingModels {
                                ProgressView().controlSize(.small)
                            } else {
                                Image(systemName: "arrow.clockwise")
                            }
                        }
                        .help("Fetch installed models from Ollama")
                        .disabled(isLoadingModels)
                    }
                }

                if !ollamaModel.isEmpty, !availableModels.contains(ollamaModel) {
                    pullCurrentModelRow
                }

                if let modelLoadStatus {
                    Text(modelLoadStatus)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                LabeledContent("Temperature") {
                    HStack(spacing: 8) {
                        Slider(value: $ollamaTemperature, in: 0...1, step: 0.1)
                            .frame(maxWidth: 220)
                        Text(String(format: "%.1f", ollamaTemperature))
                            .font(.body.monospacedDigit())
                            .frame(width: 32, alignment: .trailing)
                    }
                }
                Text("Lower values give tighter, more deterministic summaries. 0.2 is a good starting point.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ollamaInstallGuide
                if let modelLoadStatus {
                    Text(modelLoadStatus)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if let ollamaPullError {
                Text(ollamaPullError).font(.caption).foregroundStyle(.red)
            }
        }
    }

    private var suggestedOllamaModelsNotInstalled: [OllamaSuggestedModel] {
        Self.suggestedOllamaModels.filter { !availableModels.contains($0.tag) }
    }

    @ViewBuilder
    private var pullCurrentModelRow: some View {
        HStack(spacing: 8) {
            Label("Not pulled locally yet.", systemImage: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(.orange)
            Spacer()
            Button {
                Task { await pullOllamaModel(ollamaModel) }
            } label: {
                if pullingModelTag == ollamaModel {
                    HStack(spacing: 4) {
                        ProgressView().controlSize(.small)
                        Text(ollamaPullStatus ?? "Pulling…")
                    }
                } else {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.down.circle")
                        Text("Pull \(ollamaModel)")
                    }
                }
            }
            .disabled(pullingModelTag != nil)
        }
    }

    @ViewBuilder
    private var ollamaInstallGuide: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Ollama isn't reachable.", systemImage: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("1. Install Ollama from ollama.com.").font(.caption)
                Text("2. Start it (it runs in the menu bar, or run `ollama serve`).").font(.caption)
                Text("3. Pull a model with `ollama pull <name>`, then click Retry.").font(.caption)
            }
            .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                Button("Open ollama.com") {
                    if let url = URL(string: "https://ollama.com") {
                        NSWorkspace.shared.open(url)
                    }
                }
                Spacer()
                Button("Retry") {
                    Task { await refreshModels() }
                }
                .disabled(isLoadingModels)
            }
        }
    }

    private func refreshModels() async {
        guard let url = URL(string: ollamaBaseURL.isEmpty ? AppSettings.defaultOllamaBaseURL : ollamaBaseURL) else {
            modelLoadStatus = "Invalid base URL"
            ollamaReachable = false
            return
        }
        isLoadingModels = true
        defer { isLoadingModels = false }
        do {
            let models = try await OllamaClient(baseURL: url).listModels().map(\.name).sorted()
            availableModels = models
            ollamaReachable = true
            if models.isEmpty {
                modelLoadStatus = "Ollama is reachable but no models are pulled yet. Pick a Suggested model to install one."
            } else {
                modelLoadStatus = "Found \(models.count) installed model\(models.count == 1 ? "" : "s")."
            }
        } catch {
            availableModels = []
            ollamaReachable = false
            modelLoadStatus = "Couldn't reach Ollama: \(error.localizedDescription)"
        }
    }

    private func pullOllamaModel(_ tag: String) async {
        guard !tag.isEmpty,
              let url = URL(string: ollamaBaseURL.isEmpty ? AppSettings.defaultOllamaBaseURL : ollamaBaseURL) else {
            ollamaPullError = "Invalid base URL"
            return
        }
        pullingModelTag = tag
        ollamaPullError = nil
        ollamaPullStatus = "Starting…"
        defer {
            pullingModelTag = nil
            ollamaPullStatus = nil
        }
        do {
            try await OllamaClient(baseURL: url).pullModel(tag) { status in
                ollamaPullStatus = status
            }
            await refreshModels()
            ollamaModel = tag
        } catch {
            ollamaPullError = "Pull failed: \(error.localizedDescription)"
        }
    }
}

// MARK: - General tab

private struct GeneralSettingsTab: View {
    @AppStorage(SettingsKeys.notesDirectoryPath) private var notesPath: String = ""
    @AppStorage(SettingsKeys.retainAudioFiles) private var retainAudio: Bool = false
    @AppStorage(SettingsKeys.audioDirectoryPath) private var audioPath: String = ""

    var body: some View {
        Form {
            Section("Notes") {
                LabeledContent("Save location") {
                    folderRow(
                        currentPath: notesPath,
                        defaultURL: Paths.defaultNotesDirectory,
                        prompt: "Choose a folder for meeting notes",
                        onPick: { notesPath = $0 }
                    )
                }
            }

            Section("Audio") {
                Toggle("Keep audio files after transcription", isOn: $retainAudio)

                LabeledContent("Save location") {
                    folderRow(
                        currentPath: audioPath,
                        defaultURL: Paths.defaultAudioDirectory,
                        prompt: "Choose a folder for audio recordings",
                        onPick: { audioPath = $0 }
                    )
                }
                .disabled(!retainAudio)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Shared row helpers

@ViewBuilder
fileprivate func modelRow(label: String, isReady: Bool) -> some View {
    Label {
        Text(label)
    } icon: {
        Image(systemName: isReady ? "checkmark.circle.fill" : "arrow.down.circle.fill")
            .foregroundStyle(isReady ? Color.green : Color.accentColor)
    }
}

@ViewBuilder
fileprivate func folderRow(
    currentPath: String,
    defaultURL: URL,
    prompt: String,
    onPick: @escaping (String) -> Void
) -> some View {
    let url = currentPath.isEmpty ? defaultURL : URL(filePath: currentPath)
    HStack {
        Text(Paths.displayPath(url))
            .lineLimit(1)
            .truncationMode(.middle)
            .foregroundStyle(.secondary)
        Spacer()
        Button {
            _ = try? Paths.ensureDirectoryExists(url)
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } label: {
            Image(systemName: "folder")
        }
        .help("Reveal in Finder")
        Button("Choose…") {
            if let picked = pickFolder(message: prompt, initial: url) {
                onPick(picked.path(percentEncoded: false))
            }
        }
    }
}

fileprivate func pickFolder(message: String, initial: URL) -> URL? {
    let panel = NSOpenPanel()
    panel.message = message
    panel.canChooseDirectories = true
    panel.canChooseFiles = false
    panel.allowsMultipleSelection = false
    panel.canCreateDirectories = true
    panel.directoryURL = initial
    return panel.runModal() == .OK ? panel.url : nil
}
