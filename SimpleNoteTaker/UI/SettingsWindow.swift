import SwiftUI
import AppKit

struct SettingsWindow: View {
    @AppStorage(SettingsKeys.notesDirectoryPath) private var notesPath: String = ""
    @AppStorage(SettingsKeys.retainAudioFiles) private var retainAudio: Bool = false
    @AppStorage(SettingsKeys.audioDirectoryPath) private var audioPath: String = ""
    @AppStorage(SettingsKeys.llmProvider) private var llmProviderRaw: String = LLMProvider.apple.rawValue
    @AppStorage(SettingsKeys.ollamaBaseURL) private var ollamaBaseURL: String = AppSettings.defaultOllamaBaseURL
    @AppStorage(SettingsKeys.ollamaModel) private var ollamaModel: String = ""

    @State private var availableModels: [String] = []
    @State private var modelLoadStatus: String?
    @State private var isLoadingModels = false

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
        .frame(width: 560, height: 460)
        .onAppear {
            AppActivation.shared.windowDidAppear()
            if llmProviderRaw == LLMProvider.ollama.rawValue {
                Task { await refreshModels() }
            }
        }
        .onDisappear { AppActivation.shared.windowDidDisappear() }
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
