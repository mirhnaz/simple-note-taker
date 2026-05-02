import SwiftUI
import AppKit

struct SettingsWindow: View {
    @AppStorage(SettingsKeys.notesDirectoryPath) private var notesPath: String = ""
    @AppStorage(SettingsKeys.retainAudioFiles) private var retainAudio: Bool = false
    @AppStorage(SettingsKeys.audioDirectoryPath) private var audioPath: String = ""
    @AppStorage(SettingsKeys.llmProvider) private var llmProviderRaw: String = LLMProvider.apple.rawValue
    @AppStorage(SettingsKeys.ollamaBaseURL) private var ollamaBaseURL: String = AppSettings.defaultOllamaBaseURL
    @AppStorage(SettingsKeys.ollamaModel) private var ollamaModel: String = ""
    @AppStorage(SettingsKeys.transcriptionProvider) private var transcriptionProviderRaw: String = TranscriptionProvider.apple.rawValue
    @AppStorage(SettingsKeys.mlxWhisperModel) private var mlxWhisperModel: String = AppSettings.defaultMLXWhisperModel
    @AppStorage(SettingsKeys.mlxWhisperPath) private var mlxWhisperPath: String = ""

    @State private var availableModels: [String] = []
    @State private var modelLoadStatus: String?
    @State private var isLoadingModels = false
    @State private var mlxInstallPath: URL?
    @State private var mlxModelCached = false
    @State private var mlxFFmpegInstalled = false
    @State private var mlxDownloadStatus: String?
    @State private var isMLXDownloading = false

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

            Section("Audio Transcription") {
                Picker("Provider", selection: $transcriptionProviderRaw) {
                    ForEach(TranscriptionProvider.allCases) { provider in
                        Text(provider.displayName).tag(provider.rawValue)
                    }
                }
                Text("Live partials in the menu bar always use Apple SpeechAnalyzer. This setting controls the final transcript saved to the .md.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if transcriptionProviderRaw == TranscriptionProvider.mlxWhisper.rawValue {
                    LabeledContent("Model") {
                        TextField(AppSettings.defaultMLXWhisperModel, text: $mlxWhisperModel)
                            .textFieldStyle(.roundedBorder)
                    }
                    LabeledContent("mlx_whisper path (optional)") {
                        TextField("auto-detect via PATH", text: $mlxWhisperPath)
                            .textFieldStyle(.roundedBorder)
                    }

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
                                let pasteboard = NSPasteboard.general
                                pasteboard.clearContents()
                                pasteboard.setString("pip install mlx-whisper", forType: .string)
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
                        if mlxModelCached {
                            Label("Model cached", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        } else {
                            Label("Model not cached", systemImage: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                        }
                        Spacer()
                        Button {
                            Task { await downloadMLXModel() }
                        } label: {
                            if isMLXDownloading {
                                HStack(spacing: 4) {
                                    ProgressView().controlSize(.small)
                                    Text("Downloading…")
                                }
                            } else {
                                Text(mlxModelCached ? "Re-warm" : "Download model")
                            }
                        }
                        .disabled(isMLXDownloading || mlxInstallPath == nil)

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
                }
            }

            Section("Summarization") {
                Picker("Provider", selection: $llmProviderRaw) {
                    ForEach(LLMProvider.allCases) { provider in
                        Text(provider.displayName).tag(provider.rawValue)
                    }
                }

                if llmProviderRaw == LLMProvider.ollama.rawValue {
                    LabeledContent("Base URL") {
                        TextField("http://localhost:11434", text: $ollamaBaseURL)
                            .textFieldStyle(.roundedBorder)
                    }
                    LabeledContent("Model") {
                        HStack {
                            if availableModels.isEmpty {
                                TextField("e.g. llama3.2:latest", text: $ollamaModel)
                                    .textFieldStyle(.roundedBorder)
                            } else {
                                Picker("", selection: $ollamaModel) {
                                    Text("(none)").tag("")
                                    ForEach(availableModels, id: \.self) { name in
                                        Text(name).tag(name)
                                    }
                                }
                                .labelsHidden()
                            }
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
                    if let modelLoadStatus {
                        Text(modelLoadStatus)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 600, height: 720)
        .onAppear {
            AppActivation.shared.windowDidAppear()
            if llmProviderRaw == LLMProvider.ollama.rawValue {
                Task { await refreshModels() }
            }
            if transcriptionProviderRaw == TranscriptionProvider.mlxWhisper.rawValue {
                refreshMLXStatus()
            }
        }
        .onDisappear { AppActivation.shared.windowDidDisappear() }
        .onChange(of: transcriptionProviderRaw) { _, newValue in
            if newValue == TranscriptionProvider.mlxWhisper.rawValue {
                refreshMLXStatus()
            }
        }
        .onChange(of: mlxWhisperModel) { _, _ in refreshMLXStatus() }
        .onChange(of: mlxWhisperPath) { _, _ in refreshMLXStatus() }
    }

    @ViewBuilder
    private func folderRow(
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

    private func pickFolder(message: String, initial: URL) -> URL? {
        let panel = NSOpenPanel()
        panel.message = message
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.directoryURL = initial
        return panel.runModal() == .OK ? panel.url : nil
    }

    private func refreshMLXStatus() {
        mlxInstallPath = MLXWhisperEnvironment.detectInstallation(overridePath: mlxWhisperPath)
        let modelName = mlxWhisperModel.isEmpty ? AppSettings.defaultMLXWhisperModel : mlxWhisperModel
        mlxModelCached = MLXWhisperEnvironment.isModelCached(modelName)
        mlxFFmpegInstalled = MLXWhisperEnvironment.isFFmpegInstalled()
    }

    private func downloadMLXModel() async {
        guard mlxInstallPath != nil else {
            mlxDownloadStatus = "Install mlx-whisper first."
            return
        }
        isMLXDownloading = true
        mlxDownloadStatus = "Running warm-up… first run may take 1–2 minutes."
        defer {
            isMLXDownloading = false
            refreshMLXStatus()
        }
        let modelName = mlxWhisperModel.isEmpty ? AppSettings.defaultMLXWhisperModel : mlxWhisperModel
        do {
            try await MLXWhisperEnvironment.warmupDownload(model: modelName, overridePath: mlxWhisperPath)
            mlxDownloadStatus = "Model is ready."
        } catch {
            mlxDownloadStatus = "Failed: \(error.localizedDescription)"
        }
    }

    private func refreshModels() async {
        guard let url = URL(string: ollamaBaseURL.isEmpty ? AppSettings.defaultOllamaBaseURL : ollamaBaseURL) else {
            modelLoadStatus = "Invalid base URL"
            return
        }
        isLoadingModels = true
        defer { isLoadingModels = false }
        do {
            let models = try await OllamaClient(baseURL: url).listModels().map(\.name).sorted()
            availableModels = models
            if models.isEmpty {
                modelLoadStatus = "Ollama is reachable but has no installed models. Run `ollama pull <model>` first."
            } else {
                modelLoadStatus = "Found \(models.count) model\(models.count == 1 ? "" : "s")."
                if !models.contains(ollamaModel) {
                    ollamaModel = models.first ?? ""
                }
            }
        } catch {
            availableModels = []
            modelLoadStatus = "Couldn't reach Ollama: \(error.localizedDescription)"
        }
    }
}
