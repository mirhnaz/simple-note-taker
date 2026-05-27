import AVFoundation
import Foundation
import UniformTypeIdentifiers
import os

private let log = Logger(subsystem: "com.mir.SimpleNoteTaker", category: "audio-normalize")

enum AudioNormalization {
    enum NormalizationError: LocalizedError {
        case ffmpegMissing
        case ffmpegFailed(status: Int, stderr: String)
        case exportSessionUnavailable
        case exportFailed(String)

        var errorDescription: String? {
            switch self {
            case .ffmpegMissing:
                return "ffmpeg is required to import this file but wasn't found. Install with `brew install ffmpeg` and try again."
            case .ffmpegFailed(let status, let stderr):
                return "ffmpeg exited with status \(status): \(stderr.prefix(300))"
            case .exportSessionUnavailable:
                return "Couldn't initialize the audio transcoder."
            case .exportFailed(let detail):
                return "Audio transcoding failed: \(detail)"
            }
        }
    }

    /// True when the file looks like a video container (mp4, mov, m4v, mkv, …).
    /// AVAudioFile can't open these, and AVAssetExportSession's AppleM4A preset
    /// is hit-or-miss across codecs — ffmpeg is the reliable extractor.
    static func isVideoFile(_ url: URL) -> Bool {
        guard let type = UTType(filenameExtension: url.pathExtension) else { return false }
        return type.conforms(to: .movie) || type.conforms(to: .video)
    }

    /// Normalizes any source file into a transcriber-friendly format and
    /// returns a temp URL the caller owns. Prefers system ffmpeg (covers
    /// mp4/video and exotic audio codecs); falls back to AVAssetExportSession
    /// only when ffmpeg isn't installed and the source is audio-only.
    static func normalize(source: URL) async throws -> URL {
        if let ffmpeg = MLXWhisperEnvironment.detectFFmpeg() {
            return try await ffmpegExtractToWAV(source: source, ffmpeg: ffmpeg)
        }
        if isVideoFile(source) {
            // AVAssetExportSession is unreliable for arbitrary video inputs;
            // we need ffmpeg in that case.
            throw NormalizationError.ffmpegMissing
        }
        return try await transcodeToM4A(source: source)
    }

    /// Extracts a 16 kHz mono PCM .wav via ffmpeg — the format Whisper-family
    /// models expect natively, and one AVAudioFile reads without complaint.
    /// `-vn` drops any video track so video containers (mp4/mov/…) work too.
    static func ffmpegExtractToWAV(source: URL, ffmpeg: URL) async throws -> URL {
        let outputURL = FileManager.default.temporaryDirectory
            .appending(path: "snt-import-\(UUID().uuidString).wav")
        log.info("ffmpeg extracting \(source.lastPathComponent, privacy: .public) -> \(outputURL.lastPathComponent, privacy: .public)")

        let process = Process()
        process.executableURL = ffmpeg
        process.arguments = [
            "-y",
            "-i", source.path(percentEncoded: false),
            "-vn",
            "-ac", "1",
            "-ar", "16000",
            "-c:a", "pcm_s16le",
            outputURL.path(percentEncoded: false)
        ]
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = MLXWhisperEnvironment.augmentedPATH
        process.environment = env
        let stderr = Pipe()
        process.standardError = stderr
        process.standardOutput = Pipe()

        try await Task.detached {
            try process.run()
            process.waitUntilExit()
        }.value

        let stderrText = String(
            data: stderr.fileHandleForReading.readDataToEndOfFile(),
            encoding: .utf8
        ) ?? ""

        guard process.terminationStatus == 0 else {
            log.error("ffmpeg exit \(Int(process.terminationStatus), privacy: .public). stderr: \(stderrText, privacy: .public)")
            throw NormalizationError.ffmpegFailed(
                status: Int(process.terminationStatus),
                stderr: stderrText
            )
        }
        return outputURL
    }

    /// AVAssetExportSession fallback when ffmpeg isn't installed. Handles
    /// most audio-only containers (.flac, .aiff, exotic .m4a variants…) but
    /// not arbitrary video inputs reliably.
    static func transcodeToM4A(source: URL) async throws -> URL {
        let asset = AVURLAsset(url: source)
        guard let session = AVAssetExportSession(
            asset: asset,
            presetName: AVAssetExportPresetAppleM4A
        ) else {
            throw NormalizationError.exportSessionUnavailable
        }
        let outputURL = FileManager.default.temporaryDirectory
            .appending(path: "snt-import-\(UUID().uuidString).m4a")
        log.info("AVAssetExportSession transcoding \(source.lastPathComponent, privacy: .public) -> \(outputURL.lastPathComponent, privacy: .public)")
        do {
            try await session.export(to: outputURL, as: .m4a)
        } catch {
            throw NormalizationError.exportFailed(error.localizedDescription)
        }
        return outputURL
    }
}
