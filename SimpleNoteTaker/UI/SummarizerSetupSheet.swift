import AppKit
import SwiftUI

struct SummarizerSetupSheet: View {
    static let defaultOllamaModel = "gemma2:2b"
    static let defaultOllamaModelSize = "1.6 GB"

    @Environment(\.dismiss) private var dismiss
    @AppStorage(SettingsKeys.llmProvider) private var llmProviderRaw: String = LLMProvider.apple.rawValue
    @AppStorage(SettingsKeys.ollamaBaseURL) private var ollamaBaseURLString: String = AppSettings.defaultOllamaBaseURL
    @AppStorage(SettingsKeys.ollamaModel) private var ollamaModel: String = ""

    @State private var checkInProgress = true
    @State private var appleAvailable = false
    @State private var appleMessage: String?
    @State private var ollamaReachable = false
    @State private var ollamaModels: [String] = []

    @State private var isPulling = false
    @State private var pullStatus: String?
    @State private var pullError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            if checkInProgress {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Checking which providers are available…")
                        .font(.callout).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                appleSection
                Divider()
                ollamaSection
            }
            Spacer(minLength: 4)
            HStack {
                Spacer()
                Button("Close") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(20)
        .frame(width: 540)
        .task { await detectAvailability() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Set up summarization").font(.title3).bold()
            Text("Pick the model that turns transcripts into meeting summaries. You can change this any time in Settings.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Apple

    @ViewBuilder
    private var appleSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("Apple Foundation Models", systemImage: "applelogo")
            if appleAvailable {
                Label("Available — runs on-device, no download required.", systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.green)
                Button("Use Apple Foundation Models") {
                    llmProviderRaw = LLMProvider.apple.rawValue
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            } else if let appleMessage {
                Text(appleMessage)
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Ollama

    @ViewBuilder
    private var ollamaSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("Ollama (local)", systemImage: "shippingbox")
            if ollamaReachable {
                Label("Ollama is running at \(ollamaBaseURLString).", systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.green)
                if ollamaModels.isEmpty {
                    Text("No models pulled yet. \(Self.defaultOllamaModel) is a balanced general-purpose model that handles summaries well.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    pullDefaultButton
                } else {
                    Text("Use an installed model:")
                        .font(.caption)
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(ollamaModels, id: \.self) { name in
                            Button {
                                llmProviderRaw = LLMProvider.ollama.rawValue
                                ollamaModel = name
                                dismiss()
                            } label: {
                                HStack {
                                    Image(systemName: "circle.fill").font(.system(size: 5)).foregroundStyle(.secondary)
                                    Text(name)
                                    Spacer()
                                    Text("Use").foregroundStyle(.blue)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    Text("…or pull a fresh \(Self.defaultOllamaModel):")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    pullDefaultButton
                }
                if let pullError {
                    Text(pullError).font(.caption).foregroundStyle(.red)
                }
            } else {
                Label("Ollama isn't reachable at \(ollamaBaseURLString).", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                Text("Install Ollama and start it (`ollama serve`), then click Retry.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    Button("Open ollama.com") {
                        if let url = URL(string: "https://ollama.com") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    Button("Retry") {
                        Task { await detectAvailability() }
                    }
                }
            }
        }
    }

    private var pullDefaultButton: some View {
        Button {
            Task { await pullDefaultModel() }
        } label: {
            HStack(spacing: 6) {
                if isPulling {
                    ProgressView().controlSize(.small)
                    Text(pullStatus ?? "Pulling…")
                } else {
                    Image(systemName: "arrow.down.circle")
                    Text("Pull \(Self.defaultOllamaModel) (\(Self.defaultOllamaModelSize))")
                }
            }
        }
        .disabled(isPulling)
    }

    private func sectionHeader(_ title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(.headline)
    }

    // MARK: - Actions

    private func detectAvailability() async {
        checkInProgress = true
        defer { checkInProgress = false }
        if let msg = FoundationModelsAvailability.currentMessage() {
            appleAvailable = false
            appleMessage = msg
        } else {
            appleAvailable = true
            appleMessage = nil
        }
        let baseURL = URL(string: ollamaBaseURLString) ?? URL(string: AppSettings.defaultOllamaBaseURL)!
        do {
            let models = try await OllamaClient(baseURL: baseURL).listModels()
            ollamaReachable = true
            ollamaModels = models.map(\.name).sorted()
        } catch {
            ollamaReachable = false
            ollamaModels = []
        }
    }

    private func pullDefaultModel() async {
        isPulling = true
        pullError = nil
        pullStatus = "Starting…"
        defer { isPulling = false }
        let baseURL = URL(string: ollamaBaseURLString) ?? URL(string: AppSettings.defaultOllamaBaseURL)!
        do {
            try await OllamaClient(baseURL: baseURL).pullModel(Self.defaultOllamaModel) { status in
                pullStatus = status
            }
            llmProviderRaw = LLMProvider.ollama.rawValue
            ollamaModel = Self.defaultOllamaModel
            dismiss()
        } catch {
            pullError = "Pull failed: \(error.localizedDescription)"
        }
    }
}
