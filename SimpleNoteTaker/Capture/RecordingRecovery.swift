import Foundation
import os

private let log = Logger(subsystem: "com.mir.SimpleNoteTaker", category: "recovery")

/// Persists a small marker describing an in-progress recording so that, if the
/// app crashes or is force-quit before `RecordingSession.stop()` runs, the next
/// launch can detect the interrupted meeting and offer to recover it from the
/// audio already on disk.
///
/// The marker lives in Application Support (durable). The audio files it points
/// at live in the temp/audio directory; they survive a crash because `stop()`
/// — which is what would delete or finalize them — never ran.
enum RecordingRecovery {
    struct Marker: Codable, Equatable, Sendable {
        var micPath: String?
        var systemPath: String?
        var startedAt: Date
        var meetingTypeRaw: String
        var retainAudio: Bool = false

        var meetingType: MeetingType { MeetingType(rawValue: meetingTypeRaw) ?? .general }

        var audioURLs: [AudioKind: URL] {
            var result: [AudioKind: URL] = [:]
            if let micPath { result[.mic] = URL(filePath: micPath) }
            if let systemPath { result[.system] = URL(filePath: systemPath) }
            return result
        }

        /// True only if at least one referenced audio file still exists with
        /// real content — otherwise there's nothing to recover.
        var hasRecoverableAudio: Bool {
            audioURLs.values.contains { url in
                let path = url.path(percentEncoded: false)
                guard let size = try? FileManager.default.attributesOfItem(atPath: path)[.size] as? Int else { return false }
                return (size ?? 0) > 0
            }
        }
    }

    static var markerURL: URL {
        Paths.applicationSupportDirectory.appending(path: "in-progress-recording.json")
    }

    /// Records that a recording has started. Best-effort: a failure to write
    /// the marker must never block recording.
    static func begin(micURL: URL?, systemURL: URL?, startedAt: Date, meetingType: MeetingType, retainAudio: Bool) {
        let marker = Marker(
            micPath: micURL?.path(percentEncoded: false),
            systemPath: systemURL?.path(percentEncoded: false),
            startedAt: startedAt,
            meetingTypeRaw: meetingType.rawValue,
            retainAudio: retainAudio
        )
        do {
            try Paths.ensureDirectoryExists(Paths.applicationSupportDirectory)
            let data = try JSONEncoder().encode(marker)
            try data.write(to: markerURL)
        } catch {
            log.warning("couldn't write recording marker: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Clears the marker after a clean stop (or a discarded recovery).
    static func clear() {
        try? FileManager.default.removeItem(at: markerURL)
    }

    /// Returns a pending marker only if one exists AND it still points at
    /// recoverable audio; otherwise clears any stale marker and returns nil.
    static func pending() -> Marker? {
        guard let data = try? Data(contentsOf: markerURL),
              let marker = try? JSONDecoder().decode(Marker.self, from: data) else {
            return nil
        }
        guard marker.hasRecoverableAudio else {
            log.info("stale recording marker with no recoverable audio; clearing")
            clear()
            return nil
        }
        return marker
    }
}
