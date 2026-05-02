import AppKit
import SwiftUI

struct RecordingTabView: View {
    @Bindable private var controller = RecordingController.shared
    @State private var lastTranscript: String = ""

    var body: some View {
        ZStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 0) {
                header
                Divider()
                content
            }
            recordingControl
                .padding(.bottom, 24)
        }
        .task(id: controllerStateKey) {
            if case .idle = controller.state {
                await loadLastTranscript()
            }
        }
    }

    private var controllerStateKey: String {
        switch controller.state {
        case .idle: return "idle"
        case .starting: return "starting"
        case .recording: return "recording"
        case .transcribing: return "transcribing"
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            Text("Live Transcription")
                .font(.title3).bold()
            Spacer()
            recordingStatusPill
            Button {
                copyTranscriptToPasteboard()
            } label: {
                Label("Copy Transcript", systemImage: "doc.on.doc")
            }
            .disabled(displayTranscript.isEmpty)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
    }

    @ViewBuilder
    private var recordingStatusPill: some View {
        switch controller.state {
        case .recording:
            HStack(spacing: 5) {
                Circle().fill(.red).frame(width: 6, height: 6)
                Text("Recording").font(.caption).foregroundStyle(.red)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(.red.opacity(0.10)))
        case .transcribing:
            HStack(spacing: 5) {
                ProgressView().controlSize(.mini)
                Text("Processing").font(.caption).foregroundStyle(.secondary)
            }
        case .starting:
            HStack(spacing: 5) {
                ProgressView().controlSize(.mini)
                Text("Preparing").font(.caption).foregroundStyle(.secondary)
            }
        case .idle:
            EmptyView()
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        ScrollView {
            if let session = controller.session as? RecordingSession {
                liveSegmentsView(session: session)
            } else if !lastTranscript.isEmpty {
                Text(lastTranscript)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(18)
                    .font(.body)
            } else {
                idlePlaceholder
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func liveSegmentsView(session: RecordingSession) -> some View {
        let segments = session.micTranscriber.segments
        let partial = session.micTranscriber.currentPartial
        return VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(segments.enumerated()), id: \.offset) { _, seg in
                segmentCard(time: seg.startSeconds, text: seg.text, isLive: false)
            }
            if !partial.isEmpty && partial != segments.last?.text {
                segmentCard(time: nil, text: partial, isLive: true)
            }
            if segments.isEmpty && partial.isEmpty {
                Text("Listening for speech…")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .padding(18)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func segmentCard(time: TimeInterval?, text: String, isLive: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "clock")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let time {
                    Text(formatTimestamp(time))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("now")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if isLive {
                    Text("LIVE")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(.gray.opacity(0.18)))
                }
            }
            Text(text)
                .font(.body)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(.background.secondary)
        )
    }

    private var idlePlaceholder: some View {
        VStack(spacing: 12) {
            Spacer(minLength: 60)
            Image(systemName: "mic.circle")
                .font(.system(size: 56))
                .foregroundStyle(.tertiary)
            Text("Press Record to start a meeting")
                .font(.title3)
                .foregroundStyle(.secondary)
            if let warning = controller.lastWarning {
                Text(warning)
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
            if let error = controller.lastError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
            Spacer(minLength: 60)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Floating control

    @ViewBuilder
    private var recordingControl: some View {
        HStack(spacing: 14) {
            switch controller.state {
            case .idle:
                Button {
                    Task { await controller.start() }
                } label: {
                    ZStack {
                        Circle().fill(.red).frame(width: 36, height: 36)
                        Image(systemName: "mic.fill").foregroundStyle(.white)
                    }
                }
                .buttonStyle(.plain)
                .help("Start recording")
                Text("Record").font(.body).foregroundStyle(.primary)
            case .starting:
                ProgressView().controlSize(.small)
                Text("Preparing…").foregroundStyle(.secondary)
            case .recording(let startedAt):
                Button {
                    Task { await controller.stop() }
                } label: {
                    ZStack {
                        Circle().fill(.red).frame(width: 36, height: 36)
                        Image(systemName: "stop.fill").foregroundStyle(.white)
                    }
                }
                .buttonStyle(.plain)
                .help("Stop recording")
                TimelineView(.periodic(from: startedAt, by: 1)) { ctx in
                    Text(elapsed(from: startedAt, to: ctx.date))
                        .monospacedDigit()
                        .foregroundStyle(.red)
                }
            case .transcribing:
                ProgressView().controlSize(.small)
                Text("Transcribing & summarizing…").foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(.regularMaterial, in: Capsule())
        .shadow(color: .black.opacity(0.15), radius: 6, y: 2)
    }

    // MARK: - Helpers

    private var displayTranscript: String {
        if let session = controller.session as? RecordingSession {
            let segs = session.micTranscriber.segments.map { "[\(formatTimestamp($0.startSeconds))] \($0.text)" }
            return segs.joined(separator: "\n")
        }
        return lastTranscript
    }

    private func copyTranscriptToPasteboard() {
        let text = displayTranscript
        guard !text.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func formatTimestamp(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds))
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    private func elapsed(from start: Date, to end: Date) -> String {
        let total = max(0, Int(end.timeIntervalSince(start)))
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    private func loadLastTranscript() async {
        let dir = AppSettings.shared.notesDirectory
        let meetings = (try? await MeetingLibrary.load(from: dir)) ?? []
        guard let latest = meetings.first else {
            lastTranscript = ""
            return
        }
        let url = latest.transcriptURL ?? latest.legacyCombinedURL ?? latest.primaryURL
        lastTranscript = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
    }
}
