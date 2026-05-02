import AppKit
import SwiftUI

struct MenuBarView: View {
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings
    @Bindable private var controller = RecordingController.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            recordButton

            stateIndicator

            if let warning = controller.lastWarning {
                noticeRow(text: warning, color: .orange)
            }

            if let error = controller.lastError {
                noticeRow(text: error, color: .red)
            }

            if let lastURL = controller.lastTranscriptURL, controller.state == .idle {
                Divider()
                menuItem("Open Last Meeting Note", systemImage: "doc.text") {
                    NSWorkspace.shared.open(lastURL)
                }
            }

            Divider()

            menuItem("Show Window", systemImage: "macwindow") {
                AppActivation.shared.prepareToOpenWindow()
                openWindow(id: "main")
            }

            menuItem("Settings…", systemImage: "gearshape") {
                AppActivation.shared.prepareToOpenWindow()
                openSettings()
            }
            .keyboardShortcut(",", modifiers: .command)

            Divider()

            menuItem("Quit", systemImage: "power") {
                NSApp.terminate(nil)
            }
            .keyboardShortcut("q", modifiers: .command)
        }
        .padding(8)
        .frame(width: 320)
    }

    @ViewBuilder
    private var recordButton: some View {
        switch controller.state {
        case .idle:
            menuItem("Start Recording", systemImage: "record.circle") {
                Task { await controller.start() }
            }
            .keyboardShortcut("r", modifiers: [.command, .shift])
        case .starting:
            menuItem("Preparing…", systemImage: "arrow.triangle.2.circlepath") {}
                .disabled(true)
        case .recording:
            menuItem("Stop Recording", systemImage: "stop.circle.fill", tint: .red) {
                Task { await controller.stop() }
            }
            .keyboardShortcut("r", modifiers: [.command, .shift])
        case .transcribing:
            menuItem("Transcribing…", systemImage: "waveform.badge.magnifyingglass") {}
                .disabled(true)
        }
    }

    @ViewBuilder
    private var stateIndicator: some View {
        switch controller.state {
        case .recording(let startedAt):
            VStack(alignment: .leading, spacing: 4) {
                TimelineView(.periodic(from: startedAt, by: 1)) { context in
                    Label(elapsed(from: startedAt, to: context.date), systemImage: "circle.fill")
                        .font(.caption)
                        .foregroundStyle(.red)
                        .symbolEffect(.pulse, options: .repeating)
                }
                if let session = controller.session as? RecordingSession {
                    let partial = session.micTranscriber.currentPartial
                    if !partial.isEmpty {
                        Text(partial)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .frame(maxWidth: 300, alignment: .leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(.horizontal, 6)
        case .starting:
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Preparing transcription model…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 6)
        case .transcribing:
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Transcribing & summarizing…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 6)
        case .idle:
            EmptyView()
        }
    }

    @ViewBuilder
    private func noticeRow(text: String, color: Color) -> some View {
        HStack(alignment: .top, spacing: 4) {
            Text(text)
                .font(.caption)
                .foregroundStyle(color)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                controller.dismissNotices()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
            .help("Dismiss")
        }
        .padding(.horizontal, 6)
        .frame(maxWidth: 300, alignment: .leading)
    }

    @ViewBuilder
    private func menuItem(_ title: String, systemImage: String, tint: Color? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .frame(maxWidth: .infinity, alignment: .leading)
                .foregroundStyle(tint ?? .primary)
        }
        .buttonStyle(.borderless)
    }

    private func elapsed(from start: Date, to end: Date) -> String {
        let total = max(0, Int(end.timeIntervalSince(start)))
        return String(format: "Recording  %d:%02d", total / 60, total % 60)
    }
}
