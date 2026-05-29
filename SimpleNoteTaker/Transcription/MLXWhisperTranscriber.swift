import AVFoundation
import Foundation
import os

private let log = Logger(subsystem: "com.mir.SimpleNoteTaker", category: "mlx-whisper")

struct MLXWhisperTranscriber: FileTranscribing {
    let model: String
    let executablePathOverride: String
    let language: String

    init(model: String, executablePathOverride: String = "", language: String = "") {
        self.model = model
        self.executablePathOverride = executablePathOverride
        self.language = language
    }

    func transcribe(
        audioFile url: URL,
        kind: AudioKind,
        onProgress: @escaping @Sendable (Double) -> Void
    ) async throws -> [TranscriptSegment] {
        guard let exec = MLXWhisperEnvironment.detectInstallation(overridePath: executablePathOverride) else {
            throw MLXWhisperError.notInstalled
        }
        guard MLXWhisperEnvironment.isFFmpegInstalled() else {
            throw MLXWhisperError.ffmpegMissing
        }
        let outputDir = FileManager.default.temporaryDirectory.appending(path: "snt-mlx-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: outputDir) }

        log.info("transcribing \(url.lastPathComponent, privacy: .public) with model \(model, privacy: .public)")
        let totalDuration = await MLXWhisperEnvironment.loadAudioDurationSeconds(for: url) ?? 0
        let jsonURL = try await MLXWhisperEnvironment.runMLXWhisper(
            executable: exec,
            audio: url,
            model: model,
            outputDir: outputDir,
            audioDurationSeconds: totalDuration,
            language: language,
            onProgress: onProgress
        )
        let data = try Data(contentsOf: jsonURL)
        do {
            return try Self.parseSegments(jsonData: data, kind: kind)
        } catch {
            // Capture what was actually in the file before defer wipes the
            // temp dir — without this we get a useless "data isn't the
            // correct format" with no way to see the JSON.
            let preview = String(data: data.prefix(500), encoding: .utf8) ?? "(invalid UTF-8)"
            log.error("mlx_whisper JSON decode failed. file=\(jsonURL.lastPathComponent, privacy: .public) bytes=\(data.count, privacy: .public) preview=\(preview, privacy: .public)")
            throw error
        }
    }

    /// Parses a Whisper JSON output into `[TranscriptSegment]`. Tolerates the
    /// "no segments key, only text" minimal shape (single segment from 0..duration).
    static func parseSegments(jsonData: Data, kind: AudioKind) throws -> [TranscriptSegment] {
        do {
            let payload = try JSONDecoder().decode(WhisperOutput.self, from: jsonData)
            if let segments = payload.segments, !segments.isEmpty {
                return segments.map { seg in
                    TranscriptSegment(
                        kind: kind,
                        startSeconds: seg.start,
                        endSeconds: seg.end,
                        text: seg.text.trimmingCharacters(in: .whitespaces)
                    )
                }
            }
            // Fallback: single-segment from text-only JSON
            let text = payload.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return [] }
            return [TranscriptSegment(kind: kind, startSeconds: 0, endSeconds: 0, text: text)]
        } catch {
            throw MLXWhisperError.decodingFailed(underlying: error)
        }
    }

    private struct WhisperOutput: Decodable {
        let text: String
        let segments: [WhisperSegment]?
    }

    private struct WhisperSegment: Decodable {
        let start: Double
        let end: Double
        let text: String
    }
}
