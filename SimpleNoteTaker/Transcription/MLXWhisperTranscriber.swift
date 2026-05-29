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
            let payload = try JSONDecoder().decode(WhisperOutput.self, from: sanitizeNonFiniteJSON(jsonData))
            if let segments = payload.segments, !segments.isEmpty {
                return filterLoopedSegments(segments, kind: kind)
            }
            // Fallback: single-segment from text-only JSON
            let text = payload.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return [] }
            return [TranscriptSegment(kind: kind, startSeconds: 0, endSeconds: 0, text: text)]
        } catch {
            throw MLXWhisperError.decodingFailed(underlying: error)
        }
    }

    /// gzip compression ratio above which a segment is treated as a runaway
    /// repetition loop and dropped. Whisper's own "decoding failed" threshold
    /// is 2.4, but legitimate speech can sit just above that (observed 2.56),
    /// so we use a more conservative 3.0 to only catch egregious loops
    /// (observed 10.8 for a real loop) and never normal speech.
    static let loopCompressionRatioThreshold = 3.0

    /// Drops segments flagged as repetition loops by their compression ratio,
    /// collapsing each contiguous run of dropped segments into a single
    /// `[inaudible]` marker so the transcript shows a gap occurred rather than
    /// either a wall of repeated text or a silent disappearance.
    private static func filterLoopedSegments(_ segments: [WhisperSegment], kind: AudioKind) -> [TranscriptSegment] {
        var out: [TranscriptSegment] = []
        var runStart: Double?
        var runEnd: Double = 0
        var droppedCount = 0

        func flushRun() {
            guard let start = runStart else { return }
            out.append(TranscriptSegment(kind: kind, startSeconds: start, endSeconds: runEnd, text: "[inaudible]"))
            runStart = nil
        }

        for seg in segments {
            if (seg.compressionRatio ?? 0) > loopCompressionRatioThreshold {
                if runStart == nil { runStart = seg.start }
                runEnd = seg.end
                droppedCount += 1
                continue
            }
            flushRun()
            let text = seg.text.trimmingCharacters(in: .whitespaces)
            guard !text.isEmpty else { continue }
            out.append(TranscriptSegment(kind: kind, startSeconds: seg.start, endSeconds: seg.end, text: text))
        }
        flushRun()

        if droppedCount > 0 {
            log.warning("dropped \(droppedCount, privacy: .public) looped segment(s) (compression ratio > \(loopCompressionRatioThreshold, privacy: .public))")
        }
        return out
    }

    /// Python's `json.dump` (which mlx_whisper uses with the default
    /// `allow_nan=True`) emits bare `NaN`, `Infinity`, and `-Infinity` literals
    /// for non-finite floats — e.g. a segment's `compression_ratio` or
    /// `avg_logprob`. Those tokens are illegal in strict JSON, so Foundation's
    /// JSONDecoder rejects the entire document. Replace them with `0` (we don't
    /// use those metadata fields). The scan is quote-aware so the substitution
    /// never touches transcript text that happens to contain the words.
    static func sanitizeNonFiniteJSON(_ data: Data) -> Data {
        let bytes = [UInt8](data)
        let n = bytes.count
        let quote = UInt8(ascii: "\"")
        let backslash = UInt8(ascii: "\\")
        let zero = UInt8(ascii: "0")
        let tokens: [[UInt8]] = [Array("-Infinity".utf8), Array("Infinity".utf8), Array("NaN".utf8)]

        func matches(at i: Int, _ token: [UInt8]) -> Bool {
            guard i + token.count <= n else { return false }
            for k in 0..<token.count where bytes[i + k] != token[k] { return false }
            return true
        }

        var out = [UInt8]()
        out.reserveCapacity(n)
        var inString = false
        var escaped = false
        var i = 0
        while i < n {
            let b = bytes[i]
            if inString {
                out.append(b)
                if escaped { escaped = false }
                else if b == backslash { escaped = true }
                else if b == quote { inString = false }
                i += 1
                continue
            }
            if b == quote {
                inString = true
                out.append(b)
                i += 1
                continue
            }
            if let token = tokens.first(where: { matches(at: i, $0) }) {
                out.append(zero)
                i += token.count
                continue
            }
            out.append(b)
            i += 1
        }
        return Data(out)
    }

    private struct WhisperOutput: Decodable {
        let text: String
        let segments: [WhisperSegment]?
    }

    private struct WhisperSegment: Decodable {
        let start: Double
        let end: Double
        let text: String
        let compressionRatio: Double?

        enum CodingKeys: String, CodingKey {
            case start, end, text
            case compressionRatio = "compression_ratio"
        }
    }
}
