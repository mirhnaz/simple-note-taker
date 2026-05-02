import SwiftUI
import AppKit

struct SettingsWindow: View {
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
        .frame(width: 560, height: 320)
        .onAppear { AppActivation.shared.windowDidAppear() }
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
}
