import SwiftUI
import AppKit

struct MLXWhisperPreset: Identifiable, Hashable {
    let modelID: String
    let qualityHint: String

    var id: String { modelID }
    /// Repo name without the owner prefix (e.g. "whisper-base-mlx"), matching
    /// what users see on huggingface.co. Avoids inventing friendly labels like
    /// "Base"/"Large" that drift from the actual HF model IDs.
    var repoName: String {
        if let slash = modelID.firstIndex(of: "/") {
            return String(modelID[modelID.index(after: slash)...])
        }
        return modelID
    }
    var menuLabel: String { "\(repoName) — \(qualityHint)" }
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

struct StatusChip: View {
    let label: String
    let isOK: Bool
    var detail: String? = nil

    private var tone: Color { isOK ? .green : .orange }

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: isOK ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(tone)
            Text(label)
                .font(.caption)
                .fontWeight(.medium)
            if let detail, !detail.isEmpty {
                Text("· \(detail)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(
            Capsule(style: .continuous)
                .fill(tone.opacity(0.12))
        )
        .overlay(
            Capsule(style: .continuous)
                .stroke(tone.opacity(0.25), lineWidth: 1)
        )
    }
}

@ViewBuilder
fileprivate func helpRow(text: String, copyValue: String, copyLabel: String) -> some View {
    HStack(alignment: .top, spacing: 8) {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
        Button(copyLabel) {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(copyValue, forType: .string)
        }
        .controlSize(.small)
    }
}

struct StatusPill: View {
    enum Tone {
        case ready
        case action
        case warning

        var color: Color {
            switch self {
            case .ready: return .green
            case .action: return .accentColor
            case .warning: return .orange
            }
        }

        var icon: String {
            switch self {
            case .ready: return "checkmark.circle.fill"
            case .action: return "arrow.down.circle.fill"
            case .warning: return "exclamationmark.triangle.fill"
            }
        }
    }

    let tone: Tone
    let title: String
    let detail: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: tone.icon)
                .foregroundStyle(tone.color)
                .font(.title3)
                .imageScale(.large)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.callout)
                    .fontWeight(.semibold)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(tone.color.opacity(0.12))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(tone.color.opacity(0.25), lineWidth: 1)
        )
    }
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
    @AppStorage(SettingsKeys.mlxWhisperLanguage) private var mlxWhisperLanguage: String = AppSettings.defaultMLXWhisperLanguage

    @State private var mlxInstallPath: URL?
    @State private var mlxCachedSizes: [String: Int64] = [:]
    @State private var mlxDiscoveredCachedIDs: [String] = []
    @State private var mlxFFmpegInstalled = false
    @State private var mlxDownloadStatus: String?
    @State private var mlxDownloadingModel: String?

    static let mlxWhisperPresets: [MLXWhisperPreset] = [
        .init(modelID: "mlx-community/whisper-base-mlx", qualityHint: "fastest"),
        .init(modelID: "mlx-community/whisper-large-v3-turbo", qualityHint: "balanced"),
        .init(modelID: "mlx-community/whisper-large-v3-mlx", qualityHint: "highest accuracy")
    ]

    var body: some View {
        Form {
            Section {
                statusPill
            }

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
               !isMLXModelCached(newValue),
               mlxDownloadingModel == nil {
                Task { await downloadMLXModel(newValue) }
            }
        }
        .onChange(of: mlxWhisperPath) { _, _ in refreshMLXStatus() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            // Catches downloads performed via `hf` / `huggingface-cli` in a
            // terminal while Settings was still open — without this the user
            // would have to click the Refresh button.
            if transcriptionProviderRaw == TranscriptionProvider.mlxWhisper.rawValue {
                refreshMLXStatus()
            }
        }
    }

    private var statusPill: some View {
        switch transcriptionProviderRaw {
        case TranscriptionProvider.apple.rawValue:
            return StatusPill(
                tone: .ready,
                title: "Apple SpeechAnalyzer",
                detail: "Built-in, no setup required."
            )
        case TranscriptionProvider.mlxWhisper.rawValue:
            let modelDisplay = mlxModelDisplayName(mlxWhisperModel)
            if mlxInstallPath == nil {
                return StatusPill(
                    tone: .warning,
                    title: "MLX Whisper · \(modelDisplay)",
                    detail: "mlx_whisper isn't installed. Run `pip install mlx-whisper`."
                )
            }
            if !mlxFFmpegInstalled {
                return StatusPill(
                    tone: .warning,
                    title: "MLX Whisper · \(modelDisplay)",
                    detail: "ffmpeg is missing. Run `brew install ffmpeg`."
                )
            }
            if mlxDownloadingModel != nil {
                return StatusPill(
                    tone: .action,
                    title: "MLX Whisper · \(modelDisplay)",
                    detail: mlxDownloadStatus ?? "Downloading model…"
                )
            }
            if !isMLXModelCached(mlxWhisperModel) {
                return StatusPill(
                    tone: .action,
                    title: "MLX Whisper · \(modelDisplay)",
                    detail: "Model isn't cached. Select it again to download."
                )
            }
            return StatusPill(
                tone: .ready,
                title: "MLX Whisper · \(modelDisplay)",
                detail: "Ready · model cached locally."
            )
        default:
            return StatusPill(
                tone: .warning,
                title: "Unknown provider",
                detail: "Pick a transcription provider below."
            )
        }
    }

    private func mlxModelDisplayName(_ modelID: String) -> String {
        // Strip the owner prefix so the status pill stays compact and matches
        // the repo names shown in the picker.
        if let slash = modelID.firstIndex(of: "/") {
            return String(modelID[modelID.index(after: slash)...])
        }
        return modelID
    }

    @ViewBuilder
    private var mlxWhisperSection: some View {
        Section("MLX Whisper") {
            LabeledContent("Model") {
                Picker("Model", selection: $mlxWhisperModel) {
                    if !Self.mlxWhisperPresets.contains(where: { $0.modelID == mlxWhisperModel }),
                       !mlxDiscoveredCachedIDs.contains(mlxWhisperModel),
                       !mlxWhisperModel.isEmpty {
                        modelRow(
                            label: "\(mlxWhisperModel) (custom)",
                            isReady: isMLXModelCached(mlxWhisperModel),
                            trailing: mlxCachedSizes[mlxWhisperModel].map { formatBytes($0) }
                        )
                        .tag(mlxWhisperModel)
                        Divider()
                    }
                    ForEach(Self.mlxWhisperPresets) { preset in
                        modelRow(
                            label: preset.menuLabel,
                            isReady: isMLXModelCached(preset.modelID),
                            trailing: mlxCachedSizes[preset.modelID].map { formatBytes($0) }
                        )
                        .tag(preset.modelID)
                    }
                    let extras = mlxDiscoveredCachedIDs.filter { id in
                        !Self.mlxWhisperPresets.contains(where: { $0.modelID == id })
                    }
                    if !extras.isEmpty {
                        Divider()
                        Section("Already downloaded") {
                            ForEach(extras, id: \.self) { id in
                                modelRow(
                                    label: id,
                                    isReady: true,
                                    trailing: mlxCachedSizes[id].map { formatBytes($0) }
                                )
                                .tag(id)
                            }
                        }
                    }
                }
                .labelsHidden()
            }
            Text("Switching to a model that isn't cached locally starts the download automatically.")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                StatusChip(label: "mlx_whisper", isOK: mlxInstallPath != nil)
                StatusChip(label: "ffmpeg", isOK: mlxFFmpegInstalled)
                StatusChip(
                    label: "Model",
                    isOK: isMLXModelCached(mlxWhisperModel),
                    detail: mlxCachedSizes[mlxWhisperModel].map { formatBytes($0) }
                )
                Spacer()
                Button {
                    refreshMLXStatus()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .help("Re-check installation and cache")
            }

            if mlxInstallPath == nil {
                helpRow(
                    text: "mlx_whisper isn't on PATH. Run `pip install mlx-whisper` in Terminal, then click Refresh.",
                    copyValue: "pip install mlx-whisper",
                    copyLabel: "Copy install command"
                )
            }
            if !mlxFFmpegInstalled {
                helpRow(
                    text: "ffmpeg is required by mlx_whisper. Run `brew install ffmpeg` in Terminal.",
                    copyValue: "brew install ffmpeg",
                    copyLabel: "Copy"
                )
            }

            HStack(spacing: 8) {
                if isMLXModelCached(mlxWhisperModel) {
                    Button {
                        NSWorkspace.shared.activateFileViewerSelecting([MLXWhisperEnvironment.modelCacheURL(mlxWhisperModel)])
                    } label: {
                        Label("Reveal in Finder", systemImage: "folder")
                    }
                    .help("Reveal HF cache in Finder")
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
                        Text(isMLXModelCached(mlxWhisperModel) ? "Re-warm" : "Download model")
                    }
                }
                .disabled(mlxDownloadingModel != nil || mlxInstallPath == nil)
            }

            if !mlxCachedSizes.isEmpty {
                let total = mlxCachedSizes.values.reduce(0, +)
                Text("Total MLX Whisper cache: \(formatBytes(total)) across \(mlxCachedSizes.count) model\(mlxCachedSizes.count == 1 ? "" : "s").")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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

                LabeledContent("Language") {
                    TextField("en (blank = auto-detect)", text: $mlxWhisperLanguage)
                        .textFieldStyle(.roundedBorder)
                }
                Text("Two-letter language code passed to mlx_whisper as --language. Leave blank to let mlx_whisper auto-detect on the first 30s of audio (adds ~3–5s per import). Defaults to \"en\".")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func isMLXModelCached(_ modelID: String) -> Bool {
        mlxCachedSizes[modelID] != nil
    }

    private func refreshMLXStatus() {
        mlxInstallPath = MLXWhisperEnvironment.detectInstallation(overridePath: mlxWhisperPath)

        let discovered = MLXWhisperEnvironment.discoverCachedMLXWhisperModels()
        mlxDiscoveredCachedIDs = discovered.map(\.modelID)

        var sizes: [String: Int64] = [:]
        for (id, size) in discovered { sizes[id] = size }

        // Also size-check the preset IDs and the currently-selected model, in
        // case they're cached but the discovery filter didn't pick them up
        // (e.g. non-mlx-community owners surfaced via Advanced).
        var idsToCheck = Self.mlxWhisperPresets.map { $0.modelID }
        if !mlxWhisperModel.isEmpty, !idsToCheck.contains(mlxWhisperModel) {
            idsToCheck.append(mlxWhisperModel)
        }
        for modelID in idsToCheck where sizes[modelID] == nil {
            if let size = MLXWhisperEnvironment.modelDiskSize(modelID) {
                sizes[modelID] = size
            }
        }
        mlxCachedSizes = sizes
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
    @AppStorage(SettingsKeys.defaultMeetingType) private var defaultMeetingTypeRaw: String = MeetingType.general.rawValue

    @State private var availableModels: [String] = []
    @State private var modelLoadStatus: String?
    @State private var isLoadingModels = false
    @State private var ollamaReachable = false
    @State private var pullingModelTag: String?
    @State private var ollamaPullStatus: String?
    @State private var ollamaPullFraction: Double?
    @State private var ollamaPullCompletedBytes: Int?
    @State private var ollamaPullTotalBytes: Int?
    @State private var ollamaPullError: String?
    @State private var appleUnavailableMessage: String?

    // Ordered by recommendation for long-meeting summarization on Apple
    // Silicon with 16-64GB unified memory. All three have native context
    // windows large enough to ingest a multi-hour transcript in one pass,
    // avoiding the map-reduce quality loss that Apple FM's ~4K ceiling
    // would force.
    static let suggestedOllamaModels: [OllamaSuggestedModel] = [
        .init(tag: "llama3.1:8b", label: "Llama 3.1 8B", qualityHint: "recommended · 128K context"),
        .init(tag: "qwen2.5:14b", label: "Qwen 2.5 14B", qualityHint: "balanced · 32K context"),
        .init(tag: "qwen2.5:32b", label: "Qwen 2.5 32B", qualityHint: "highest accuracy · 32K context")
    ]

    var body: some View {
        Form {
            Section {
                statusPill
            }

            Section {
                Picker("Provider", selection: $llmProviderRaw) {
                    ForEach(LLMProvider.allCases) { provider in
                        Text(provider.displayName).tag(provider.rawValue)
                    }
                }

                if llmProviderRaw == LLMProvider.apple.rawValue {
                    appleStatusRow
                    Text("Apple Foundation Models is on-device with a ~4K-token context. Meetings longer than ~10 minutes can overflow it — switch to Ollama with a large-context model (e.g. Llama 3.1 8B at 128K) for full-length summarization.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Section("Meeting type") {
                Picker("Default for new recordings", selection: $defaultMeetingTypeRaw) {
                    ForEach(MeetingType.allCases) { type in
                        Text(type.displayName).tag(type.rawValue)
                    }
                }
                Text("Tailors the summary prompt and is written into each meeting's reading.md / transcript.json so downstream agents can route on it. Imports let you pick per-file; live recordings use this default.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if llmProviderRaw == LLMProvider.ollama.rawValue {
                ollamaSection
            }
        }
        .formStyle(.grouped)
        .onAppear {
            refreshAppleAvailability()
            if llmProviderRaw == LLMProvider.ollama.rawValue {
                Task { await refreshModels() }
            }
        }
        .onChange(of: llmProviderRaw) { _, newValue in
            if newValue == LLMProvider.apple.rawValue {
                refreshAppleAvailability()
            }
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

    private var statusPill: some View {
        switch llmProviderRaw {
        case LLMProvider.apple.rawValue:
            if let msg = appleUnavailableMessage {
                return StatusPill(
                    tone: .warning,
                    title: "Apple Foundation Models",
                    detail: msg
                )
            }
            return StatusPill(
                tone: .ready,
                title: "Apple Foundation Models",
                detail: "Ready · runs on-device."
            )
        case LLMProvider.ollama.rawValue:
            if !ollamaReachable {
                return StatusPill(
                    tone: .warning,
                    title: "Ollama",
                    detail: "Not reachable at \(ollamaBaseURL)."
                )
            }
            if let tag = pullingModelTag {
                return StatusPill(
                    tone: .action,
                    title: "Ollama · \(tag)",
                    detail: ollamaPullStatus ?? "Pulling model…"
                )
            }
            if ollamaModel.isEmpty {
                return StatusPill(
                    tone: .warning,
                    title: "Ollama",
                    detail: "Pick a model to enable summarization."
                )
            }
            if !availableModels.contains(ollamaModel) {
                return StatusPill(
                    tone: .action,
                    title: "Ollama · \(ollamaModel)",
                    detail: "Model isn't pulled yet."
                )
            }
            return StatusPill(
                tone: .ready,
                title: "Ollama · \(ollamaModel)",
                detail: "Ready · running at \(ollamaBaseURL)."
            )
        default:
            return StatusPill(
                tone: .warning,
                title: "Unknown provider",
                detail: "Pick a summarization provider below."
            )
        }
    }

    @ViewBuilder
    private var appleStatusRow: some View {
        if let msg = appleUnavailableMessage {
            HStack(spacing: 8) {
                Label(msg, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .font(.caption)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
                Button("Open Apple Intelligence") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.intelligence") {
                        NSWorkspace.shared.open(url)
                    }
                }
                Button {
                    refreshAppleAvailability()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .help("Re-check Apple Intelligence availability")
            }
        } else {
            HStack(spacing: 8) {
                Label("Available — runs on-device, no download required.", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.caption)
                Spacer()
                Button {
                    refreshAppleAvailability()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .help("Re-check Apple Intelligence availability")
            }
        }
    }

    private func refreshAppleAvailability() {
        appleUnavailableMessage = FoundationModelsAvailability.currentMessage()
        // User may have toggled Apple Intelligence outside the app — push the
        // banner's status through even if no UserDefaults key changed.
        Task { await RecordingController.shared.refreshSummarizerStatus() }
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
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Label(
                    pullingModelTag == ollamaModel ? "Pulling \(ollamaModel)…" : "Not pulled locally yet.",
                    systemImage: pullingModelTag == ollamaModel ? "arrow.down.circle.fill" : "exclamationmark.triangle.fill"
                )
                .font(.caption)
                .foregroundStyle(pullingModelTag == ollamaModel ? Color.accentColor : Color.orange)
                Spacer()
                Button {
                    Task { await pullOllamaModel(ollamaModel) }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.down.circle")
                        Text("Pull \(ollamaModel)")
                    }
                }
                .disabled(pullingModelTag != nil)
            }
            if pullingModelTag == ollamaModel {
                pullProgressView
            }
        }
    }

    @ViewBuilder
    private var pullProgressView: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let fraction = ollamaPullFraction {
                ProgressView(value: fraction)
                    .progressViewStyle(.linear)
            } else {
                ProgressView()
                    .progressViewStyle(.linear)
            }
            HStack {
                Text(ollamaPullStatus ?? "Working…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(pullByteLabel)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var pullByteLabel: String {
        guard let total = ollamaPullTotalBytes, total > 0 else { return "" }
        let completed = ollamaPullCompletedBytes ?? 0
        return "\(formatBytes(Int64(completed))) / \(formatBytes(Int64(total)))"
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
        ollamaPullFraction = nil
        ollamaPullCompletedBytes = nil
        ollamaPullTotalBytes = nil
        defer {
            pullingModelTag = nil
            ollamaPullStatus = nil
            ollamaPullFraction = nil
            ollamaPullCompletedBytes = nil
            ollamaPullTotalBytes = nil
        }
        do {
            try await OllamaClient(baseURL: url).pullModel(tag) { progress in
                ollamaPullStatus = progress.status
                ollamaPullFraction = progress.fraction
                ollamaPullCompletedBytes = progress.completedBytes
                ollamaPullTotalBytes = progress.totalBytes
            }
            await refreshModels()
            ollamaModel = tag
            // Covers the case where the just-pulled tag equals the already-
            // selected model: no @AppStorage change fires, so the banner's
            // .task(id:) wouldn't re-probe on its own.
            await RecordingController.shared.refreshSummarizerStatus()
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
fileprivate func modelRow(label: String, isReady: Bool, trailing: String? = nil) -> some View {
    Label {
        if let trailing, !trailing.isEmpty {
            Text("\(label)  ·  \(trailing)")
        } else {
            Text(label)
        }
    } icon: {
        // Picker on macOS renders these in NSMenu, which strips
        // .foregroundStyle from SF Symbol images and re-tints them as
        // templates. Pre-rendering as an NSImage with palette colors baked
        // in (and isTemplate = false) preserves the green/accent tint.
        coloredSFSymbol(
            isReady ? "checkmark.circle.fill" : "arrow.down.circle.fill",
            color: isReady ? .systemGreen : .controlAccentColor
        )
    }
}

fileprivate func coloredSFSymbol(_ name: String, color: NSColor) -> Image {
    let base = NSImage(systemSymbolName: name, accessibilityDescription: nil) ?? NSImage()
    let cfg = NSImage.SymbolConfiguration(paletteColors: [color])
    let result = base.withSymbolConfiguration(cfg) ?? base
    result.isTemplate = false
    return Image(nsImage: result)
}

fileprivate func formatBytes(_ bytes: Int64) -> String {
    let formatter = ByteCountFormatter()
    formatter.allowedUnits = [.useMB, .useGB]
    formatter.countStyle = .file
    return formatter.string(fromByteCount: bytes)
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
