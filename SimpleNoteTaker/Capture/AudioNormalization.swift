import AVFoundation
import Foundation
import os

private let log = Logger(subsystem: "com.mir.SimpleNoteTaker", category: "audio-normalize")

enum AudioNormalization {
    enum NormalizationError: LocalizedError {
        case exportSessionUnavailable
        case exportFailed(String)

        var errorDescription: String? {
            switch self {
            case .exportSessionUnavailable:
                return "Couldn't initialize the audio transcoder."
            case .exportFailed(let detail):
                return "Audio transcoding failed: \(detail)"
            }
        }
    }

    /// Re-encodes the source audio to .m4a (AAC) via AVAssetExportSession.
    /// Used as a fallback when a transcriber rejects the original format.
    /// Caller owns the returned temp file and should remove it when done.
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
        log.info("transcoding \(source.lastPathComponent, privacy: .public) -> \(outputURL.lastPathComponent, privacy: .public)")
        do {
            try await session.export(to: outputURL, as: .m4a)
        } catch {
            throw NormalizationError.exportFailed(error.localizedDescription)
        }
        return outputURL
    }
}
