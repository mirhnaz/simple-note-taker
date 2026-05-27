import AppKit
import SwiftUI

/// Per-meeting detail window: shows the AI summary cards (headline, summary,
/// key points, action items, decisions). Lives in its own Window scene so
/// multiple meetings can be open side-by-side. Loaded by recordedAt date.
struct MeetingDetailView: View {
    var meetingDate: Date

    @State private var summary: MeetingSummary?
    @State private var transcriptText: String = ""
    @State private var summaryURL: URL?
    @State private var readingURL: URL?
    @State private var isLoading = false
    @State private var isRegenerating = false
    @State private var availableOllamaModels: [String] = []
    @State private var lastError: String?
    /// Snapshot of the summary file content from before the most recent
    /// Regenerate. Cleared when the user undoes or when a different meeting
    /// is loaded.
    @State private var previousSummaryFileContent: String?
    @State private var previousModelLabel: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            ScrollView {
                if let summary {
                    cards(summary)
                } else if isLoading {
                    ProgressView().padding(60)
                } else {
                    placeholder
                }
                if let lastError {
                    Text(lastError)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .padding(.horizontal, 18)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationTitle(navigationTitle)
        .background(Color.appWindowBackground)
        .task(id: meetingDate) { await loadMeeting() }
        .task { await refreshOllamaModels() }
    }

    private var navigationTitle: String {
        if let title = summary?.title, !title.isEmpty { return title }
        return meetingDate.formatted(date: .abbreviated, time: .shortened)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 10) {
            Label("AI Summary", systemImage: "sparkles")
                .font(.title3.bold())
                .foregroundStyle(.purple)
            Spacer()
            if previousSummaryFileContent != nil {
                Button {
                    undoRegenerate()
                } label: {
                    Label("Undo regenerate", systemImage: "arrow.uturn.backward")
                }
                .help(previousModelLabel.map { "Restore the summary from before \($0)" } ?? "Restore the previous summary")
            }
            Button {
                openReadingFile()
            } label: {
                Label("Open Reading File", systemImage: "doc.text")
            }
            .disabled(readingURL == nil)
            .help("Open the clean prose version of this meeting (no timestamps) for reading and search")

            Button {
                copyMarkdown()
            } label: {
                Label("Copy as Markdown", systemImage: "doc.on.doc")
            }
            .disabled(summary == nil)

            regenerateMenu
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
    }

    private var regenerateMenu: some View {
        Menu {
            Button("Apple Foundation Models") {
                Task { await regenerate(provider: .apple, ollamaModelOverride: nil, modelLabel: "Apple Foundation Models") }
            }
            if !availableOllamaModels.isEmpty {
                Section("Ollama") {
                    ForEach(availableOllamaModels, id: \.self) { name in
                        Button(name) {
                            Task { await regenerate(provider: .ollama, ollamaModelOverride: name, modelLabel: "Ollama: \(name)") }
                        }
                    }
                }
            }
            Divider()
            Button("Refresh Ollama models") {
                Task { await refreshOllamaModels() }
            }
        } label: {
            HStack(spacing: 5) {
                if isRegenerating {
                    ProgressView().controlSize(.mini)
                } else {
                    Image(systemName: "arrow.clockwise")
                }
                Text("Regenerate")
            }
        }
        .menuStyle(.borderlessButton)
        .disabled(summary == nil || isRegenerating || transcriptText.isEmpty)
        .help("Re-run the summarizer; pick a model to override the default for this regeneration only.")
    }

    // MARK: - Cards

    private func cards(_ summary: MeetingSummary) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            if !summary.title.isEmpty {
                Text(summary.title)
                    .font(.title)
                    .bold()
            }
            if !summary.headline.isEmpty {
                summaryCard(title: "Headline") {
                    Text(summary.headline)
                        .font(.title3)
                        .italic()
                }
            }
            if !summary.summary.isEmpty {
                summaryCard(title: "Summary") {
                    Text(summary.summary)
                }
            }
            summaryCard(title: "Key Points") {
                bulletList(summary.keyPoints)
            }
            summaryCard(title: "Action Items") {
                bulletList(summary.actionItems)
            }
            summaryCard(title: "Decisions") {
                bulletList(summary.decisions)
            }
        }
        .padding(18)
    }

    private func summaryCard<Content: View>(
        title: String,
        @ViewBuilder _ content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
                .foregroundStyle(.secondary)
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.appCardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(.gray.opacity(0.18), lineWidth: 1)
        )
    }

    @ViewBuilder
    private func bulletList(_ items: [String]) -> some View {
        if items.isEmpty {
            Text("(none)")
                .foregroundStyle(.secondary)
                .italic()
        } else {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(items, id: \.self) { item in
                    HStack(alignment: .top, spacing: 8) {
                        Text("•").foregroundStyle(.secondary)
                        Text(item)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
    }

    private var placeholder: some View {
        VStack(spacing: 12) {
            Spacer(minLength: 60)
            Image(systemName: "sparkles")
                .font(.system(size: 56))
                .foregroundStyle(.tertiary)
            Text("No summary yet")
                .font(.title3)
                .foregroundStyle(.secondary)
            Spacer(minLength: 60)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Loading + regenerate

    private func loadMeeting() async {
        isLoading = true
        defer { isLoading = false }
        // A different meeting just loaded; the prior undo backup no longer
        // applies and would restore the wrong file.
        previousSummaryFileContent = nil
        previousModelLabel = nil
        let dir = AppSettings.shared.notesDirectory
        let meetings = (try? await MeetingLibrary.load(from: dir)) ?? []
        guard let target = meetings.first(where: { $0.recordedAt == meetingDate }) else {
            summary = nil
            summaryURL = nil
            readingURL = nil
            transcriptText = ""
            return
        }
        let summarySource = target.summaryURL ?? target.legacyCombinedURL
        if let summarySource {
            summaryURL = summarySource
            let content = (try? String(contentsOf: summarySource, encoding: .utf8)) ?? ""
            summary = MeetingSummaryParser.parse(content: content)
        }
        readingURL = target.readingURL
        let transcriptSource = target.transcriptURL ?? target.legacyCombinedURL
        if let transcriptSource {
            transcriptText = (try? String(contentsOf: transcriptSource, encoding: .utf8)) ?? ""
        } else {
            transcriptText = ""
        }
    }

    private func refreshOllamaModels() async {
        let url = AppSettings.shared.ollamaBaseURL
        let models = (try? await OllamaClient(baseURL: url).listModels()) ?? []
        availableOllamaModels = models.map(\.name).sorted()
    }

    private func regenerate(provider: LLMProvider, ollamaModelOverride: String?, modelLabel: String) async {
        guard !transcriptText.isEmpty else { return }
        isRegenerating = true
        defer { isRegenerating = false }
        lastError = nil

        let summarizer: any Summarizing
        switch provider {
        case .apple:
            if let message = FoundationModelsAvailability.currentMessage() {
                lastError = message
                return
            }
            summarizer = FoundationModelsSummarizer()
        case .ollama:
            let modelName = ollamaModelOverride ?? AppSettings.shared.ollamaModel
            guard !modelName.isEmpty else {
                lastError = "Pick an Ollama model in Settings first."
                return
            }
            summarizer = OllamaSummarizer(baseURL: AppSettings.shared.ollamaBaseURL, model: modelName)
        }

        let newSummary = await summarizer.summarize(transcript: transcriptText)
        guard let newSummary else {
            lastError = "The summarizer returned nothing. Check the model is available and try again."
            return
        }
        do {
            // Snapshot the on-disk content from before this regenerate so the
            // user can revert if they don't like the new output.
            if let summaryURL,
               let existing = try? String(contentsOf: summaryURL, encoding: .utf8) {
                previousSummaryFileContent = existing
                previousModelLabel = modelLabel
            }
            let dir = AppSettings.shared.notesDirectory
            let url = try MarkdownWriter.writeSummary(meetingDate: meetingDate, summary: newSummary, to: dir)
            summaryURL = url
            summary = newSummary
        } catch {
            lastError = "Couldn't save regenerated summary: \(error.localizedDescription)"
        }
    }

    private func undoRegenerate() {
        guard let backup = previousSummaryFileContent, let summaryURL else { return }
        do {
            try backup.write(to: summaryURL, atomically: true, encoding: .utf8)
            summary = MeetingSummaryParser.parse(content: backup)
            previousSummaryFileContent = nil
            previousModelLabel = nil
        } catch {
            lastError = "Couldn't restore the previous summary: \(error.localizedDescription)"
        }
    }

    private func copyMarkdown() {
        guard let url = summaryURL else { return }
        let content = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        guard !content.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(content, forType: .string)
    }

    private func openReadingFile() {
        guard let url = readingURL else { return }
        NSWorkspace.shared.open(url)
    }
}
