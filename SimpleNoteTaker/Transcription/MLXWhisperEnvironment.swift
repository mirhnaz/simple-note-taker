import AVFoundation
import Foundation
import os

private let log = Logger(subsystem: "com.mir.SimpleNoteTaker", category: "mlx-whisper")

enum MLXWhisperEnvironment {
    /// Common locations where pip / Homebrew / conda put binaries. GUI apps
    /// launched from Dock/Finder inherit a stripped-down PATH and won't see
    /// these via `which`, so we probe them directly.
    static let candidateBinDirs: [String] = {
        let home = NSHomeDirectory()
        var dirs = [
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "\(home)/.local/bin",
            "\(home)/.pyenv/shims",
            "\(home)/miniforge3/bin",
            "\(home)/miniconda3/bin",
            "\(home)/anaconda3/bin"
        ]
        for v in ["3.9", "3.10", "3.11", "3.12", "3.13", "3.14"] {
            dirs.append("\(home)/Library/Python/\(v)/bin")
        }
        return dirs
    }()

    /// Resolves to a usable `mlx_whisper` executable: first the user override,
    /// then a sweep of `candidateBinDirs`, then `/usr/bin/env which` as a last
    /// resort. Returns nil if nothing is found.
    static func detectInstallation(overridePath: String = "") -> URL? {
        let trimmedOverride = overridePath.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedOverride.isEmpty {
            let url = URL(filePath: trimmedOverride)
            return FileManager.default.isExecutableFile(atPath: url.path(percentEncoded: false)) ? url : nil
        }
        for dir in candidateBinDirs {
            let candidate = "\(dir)/mlx_whisper"
            if FileManager.default.isExecutableFile(atPath: candidate) {
                return URL(filePath: candidate)
            }
        }
        return whichOnPath("mlx_whisper")
    }

    /// PATH augmented with `candidateBinDirs` and the system PATH. mlx_whisper
    /// is a Python script — its child python interpreter and any imported
    /// console scripts need PATH set or they fall back to /usr/bin and break.
    /// Specifically, mlx_whisper shells out to `ffmpeg` to load any audio
    /// file, so ffmpeg must be reachable via this PATH.
    static var augmentedPATH: String {
        let existing = ProcessInfo.processInfo.environment["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"
        let extras = candidateBinDirs.joined(separator: ":")
        return "\(extras):\(existing)"
    }

    /// True if `ffmpeg` is reachable via the augmented PATH. mlx_whisper hard-
    /// requires ffmpeg internally, so we surface this independently in Settings.
    static func isFFmpegInstalled() -> Bool {
        detectFFmpeg() != nil
    }

    /// Resolves the path to the system `ffmpeg` binary, or nil if not found.
    /// Used by ImportSession to extract / normalize audio for transcription.
    static func detectFFmpeg() -> URL? {
        for dir in candidateBinDirs {
            let candidate = "\(dir)/ffmpeg"
            if FileManager.default.isExecutableFile(atPath: candidate) {
                return URL(filePath: candidate)
            }
        }
        return whichOnPath("ffmpeg")
    }

    /// Resolves the Hugging Face hub cache root, honoring `HF_HUB_CACHE`
    /// (most specific), then `HF_HOME`, then the default `~/.cache/huggingface/hub`.
    /// huggingface_hub respects this same precedence.
    static var hubCacheURL: URL {
        let env = ProcessInfo.processInfo.environment
        if let explicit = env["HF_HUB_CACHE"], !explicit.isEmpty {
            return URL(filePath: (explicit as NSString).expandingTildeInPath)
        }
        if let hfHome = env["HF_HOME"], !hfHome.isEmpty {
            return URL(filePath: (hfHome as NSString).expandingTildeInPath).appending(path: "hub")
        }
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appending(path: ".cache/huggingface/hub")
    }

    /// True if Hugging Face has the model snapshot directory locally.
    /// HF caches under: <hubCache>/models--<owner>--<name>/snapshots/<rev>/
    /// (replacing all `/` in the repo id with `--`).
    static func isModelCached(_ name: String, fileManager: FileManager = .default) -> Bool {
        let cacheURL = modelCacheURL(name)
        var isDir: ObjCBool = false
        guard fileManager.fileExists(atPath: cacheURL.path(percentEncoded: false), isDirectory: &isDir), isDir.boolValue else {
            return false
        }
        // The dir exists; require at least one snapshot subdirectory with files in it.
        let snapshotsDir = cacheURL.appending(path: "snapshots")
        guard let snapshots = try? fileManager.contentsOfDirectory(atPath: snapshotsDir.path(percentEncoded: false)) else {
            return false
        }
        return snapshots.contains { snap in
            let dir = snapshotsDir.appending(path: snap)
            let contents = (try? fileManager.contentsOfDirectory(atPath: dir.path(percentEncoded: false))) ?? []
            return !contents.isEmpty
        }
    }

    static func modelCacheURL(_ name: String) -> URL {
        let folder = "models--" + name.replacingOccurrences(of: "/", with: "--")
        return hubCacheURL.appending(path: folder)
    }

    /// Scans the HF hub cache for already-downloaded MLX whisper models.
    /// Returns (modelID, byteSize) for each `models--mlx-community--whisper*`
    /// folder that has snapshot content. Lets the picker surface models the
    /// user pulled with `hf` / `huggingface-cli` directly, even if they aren't
    /// in the app's preset list.
    static func discoverCachedMLXWhisperModels(fileManager: FileManager = .default) -> [(modelID: String, size: Int64)] {
        let hub = hubCacheURL
        let prefix = "models--mlx-community--whisper"
        guard let entries = try? fileManager.contentsOfDirectory(atPath: hub.path(percentEncoded: false)) else {
            return []
        }
        var results: [(modelID: String, size: Int64)] = []
        for entry in entries where entry.hasPrefix(prefix) {
            // HF replaces each `/` in the repo id with `--`. Repo ids are always
            // `owner/name` (one slash), so there's exactly one `--` separator
            // after stripping the `models--` prefix.
            let stripped = String(entry.dropFirst("models--".count))
            guard let sep = stripped.range(of: "--") else { continue }
            let owner = String(stripped[..<sep.lowerBound])
            let name = String(stripped[sep.upperBound...])
            let modelID = "\(owner)/\(name)"
            guard isModelCached(modelID, fileManager: fileManager) else { continue }
            let size = modelDiskSize(modelID, fileManager: fileManager) ?? 0
            results.append((modelID, size))
        }
        return results.sorted { $0.modelID < $1.modelID }
    }

    /// Sums the sizes of every blob in the HF cache for this model. The
    /// snapshot dir contains only symlinks; the real bytes live in `blobs/`,
    /// so we walk that instead. Returns nil if the model isn't downloaded.
    static func modelDiskSize(_ name: String, fileManager: FileManager = .default) -> Int64? {
        let blobsDir = modelCacheURL(name).appending(path: "blobs")
        guard fileManager.fileExists(atPath: blobsDir.path(percentEncoded: false)),
              let enumerator = fileManager.enumerator(
                at: blobsDir,
                includingPropertiesForKeys: [.totalFileAllocatedSizeKey, .isRegularFileKey]
              ) else {
            return nil
        }
        var totalSize: Int64 = 0
        var foundAny = false
        for case let url as URL in enumerator {
            guard
                let values = try? url.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .isRegularFileKey]),
                values.isRegularFile == true,
                let size = values.totalFileAllocatedSize
            else { continue }
            totalSize += Int64(size)
            foundAny = true
        }
        return foundAny ? totalSize : nil
    }

    /// Generates a 0.5s silent .m4a in tmp, runs mlx-whisper on it (which forces
    /// the model to download if not cached), then deletes the silent file and
    /// any output JSON. Throws if mlx-whisper isn't installed or returns non-zero.
    static func warmupDownload(model: String, overridePath: String = "") async throws {
        guard let exec = detectInstallation(overridePath: overridePath) else {
            throw MLXWhisperError.notInstalled
        }
        let tmpDir = FileManager.default.temporaryDirectory.appending(path: "snt-mlx-warmup-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let silenceURL = tmpDir.appending(path: "silence.m4a")
        try writeSilentM4A(durationSeconds: 0.5, to: silenceURL)

        _ = try await runMLXWhisper(executable: exec, audio: silenceURL, model: model, outputDir: tmpDir)
        log.info("warmup completed for model: \(model, privacy: .public)")
    }

    /// Loads the playable duration (in seconds) of an audio/video file via
    /// AVURLAsset. Returns nil if the duration is indeterminate or load fails.
    static func loadAudioDurationSeconds(for url: URL) async -> Double? {
        let asset = AVURLAsset(url: url)
        do {
            let duration = try await asset.load(.duration)
            let seconds = duration.seconds
            guard seconds.isFinite, seconds > 0 else { return nil }
            return seconds
        } catch {
            return nil
        }
    }

    /// Runs mlx-whisper and returns the path to the .json output it produced.
    /// While running, streams stdout/stderr live and calls `onProgress` with a
    /// 0.0...1.0 fraction parsed from mlx_whisper's `[mm:ss.xxx --> mm:ss.xxx]`
    /// segment prints (divided by `audioDurationSeconds`). If the duration
    /// isn't known (0), progress just never fires.
    static func runMLXWhisper(
        executable: URL,
        audio: URL,
        model: String,
        outputDir: URL,
        audioDurationSeconds: Double = 0,
        onProgress: @escaping @Sendable (Double) -> Void = { _ in }
    ) async throws -> URL {
        let process = Process()
        process.executableURL = executable
        process.arguments = [
            audio.path(percentEncoded: false),
            "--model", model,
            "--output-format", "json",
            "--output-dir", outputDir.path(percentEncoded: false)
        ]
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = augmentedPATH
        // When stdout is a pipe (not a TTY), CPython switches to block
        // buffering, so mlx_whisper's per-segment "[HH:MM:SS.mmm --> ...]"
        // prints sit in an ~8KB buffer until enough have accumulated. That
        // makes our live-progress drain useless. PYTHONUNBUFFERED=1 forces a
        // flush on every print so the UI updates segment-by-segment.
        env["PYTHONUNBUFFERED"] = "1"
        process.environment = env
        // Keep the subprocess on performance cores. Without this it inherits
        // the parent Task's QoS (typically .utility under Swift concurrency),
        // and macOS routes the work to efficiency cores and throttles Metal
        // scheduling — which manifests as long transcription times with both
        // CPU and GPU sitting nearly idle in Activity Monitor.
        process.qualityOfService = .userInitiated
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        let stdoutAccumulator = LineAccumulator(onLine: { line in
            handleMLXProgressLine(line, durationSeconds: audioDurationSeconds, onProgress: onProgress)
        })
        let stderrAccumulator = LineAccumulator(onLine: { line in
            handleMLXProgressLine(line, durationSeconds: audioDurationSeconds, onProgress: onProgress)
        })

        async let stdoutDrain: Void = drain(handle: stdout.fileHandleForReading, into: stdoutAccumulator)
        async let stderrDrain: Void = drain(handle: stderr.fileHandleForReading, into: stderrAccumulator)

        SubprocessRegistry.shared.track(process)
        try await Task.detached(priority: .userInitiated) {
            try process.run()
            process.waitUntilExit()
        }.value

        _ = await (stdoutDrain, stderrDrain)

        let stdoutText = stdoutAccumulator.text
        let stderrText = stderrAccumulator.text

        guard process.terminationStatus == 0 else {
            log.error("mlx_whisper exit \(Int(process.terminationStatus), privacy: .public). stderr: \(stderrText, privacy: .public)")
            throw MLXWhisperError.processFailed(status: Int(process.terminationStatus), stderr: stderrText)
        }
        if !stderrText.isEmpty {
            log.info("mlx_whisper stderr: \(stderrText, privacy: .public)")
        }

        let basename = (audio.lastPathComponent as NSString).deletingPathExtension
        let expected = outputDir.appending(path: "\(basename).json")
        if FileManager.default.fileExists(atPath: expected.path(percentEncoded: false)) {
            return expected
        }
        // Fallback: pick any .json mlx_whisper happened to drop in the dir.
        if let any = (try? FileManager.default.contentsOfDirectory(atPath: outputDir.path(percentEncoded: false)))?
            .first(where: { $0.hasSuffix(".json") }) {
            return outputDir.appending(path: any)
        }
        let listing = (try? FileManager.default.contentsOfDirectory(atPath: outputDir.path(percentEncoded: false))) ?? []
        log.error("no json output. dir contents: \(listing, privacy: .public). stdout: \(stdoutText, privacy: .public). stderr: \(stderrText, privacy: .public)")
        throw MLXWhisperError.outputMissing(expected: expected)
    }

    private static func drain(handle: FileHandle, into accumulator: LineAccumulator) async {
        do {
            for try await line in handle.bytes.lines {
                accumulator.append(line)
            }
        } catch {
            // pipe closed early or read failed — fine, we'll surface whatever we got.
        }
    }

    /// Matches the end-timestamp in mlx_whisper's segment print, e.g.
    /// "[00:01.234 --> 00:05.678] Hello" or "[01:02:03.456 --> 01:02:08.000] …".
    private static let mlxSegmentRegex = #/-->\s*((?:\d+:)?\d+:\d+\.\d+)\]/#

    private static func handleMLXProgressLine(
        _ line: String,
        durationSeconds: Double,
        onProgress: @Sendable (Double) -> Void
    ) {
        guard durationSeconds > 0 else { return }
        guard let match = try? mlxSegmentRegex.firstMatch(in: line) else { return }
        let endStr = String(match.output.1)
        guard let endTime = parseTimestamp(endStr) else { return }
        let fraction = min(1.0, max(0.0, endTime / durationSeconds))
        onProgress(fraction)
    }

    private static func parseTimestamp(_ s: String) -> Double? {
        let parts = s.split(separator: ":").map(String.init)
        guard let last = parts.last, let seconds = Double(last) else { return nil }
        var total = seconds
        var multiplier = 60.0
        for part in parts.dropLast().reversed() {
            guard let n = Double(part) else { return nil }
            total += n * multiplier
            multiplier *= 60
        }
        return total
    }

    private static func whichOnPath(_ name: String) -> URL? {
        let process = Process()
        process.executableURL = URL(filePath: "/usr/bin/env")
        process.arguments = ["which", name]
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = augmentedPATH
        process.environment = env
        let stdout = Pipe()
        process.standardOutput = stdout
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }
        guard process.terminationStatus == 0 else { return nil }
        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !path.isEmpty else { return nil }
        return URL(filePath: path)
    }

    /// Writes a duration-second silent AAC .m4a to the given URL.
    private static func writeSilentM4A(durationSeconds: Double, to url: URL) throws {
        let sampleRate = 44_100.0
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue
        ]
        let file = try AVAudioFile(forWriting: url, settings: settings, commonFormat: format.commonFormat, interleaved: format.isInterleaved)
        let frameCount = AVAudioFrameCount(durationSeconds * sampleRate)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            throw MLXWhisperError.silenceGenerationFailed
        }
        buffer.frameLength = frameCount
        // PCM buffer is zero-initialized → already silent.
        try file.write(from: buffer)
    }
}

/// Drains a child process pipe into a single accumulated string while
/// invoking `onLine` for each `\n`-terminated line as it arrives.
/// Thread-safe — the drain task reads from a private GCD queue under the hood.
final class LineAccumulator: @unchecked Sendable {
    private let lock = NSLock()
    private var fullText = ""
    private let onLine: @Sendable (String) -> Void

    init(onLine: @escaping @Sendable (String) -> Void) {
        self.onLine = onLine
    }

    func append(_ line: String) {
        lock.lock()
        fullText.append(line)
        fullText.append("\n")
        lock.unlock()
        onLine(line)
    }

    var text: String {
        lock.lock(); defer { lock.unlock() }
        return fullText
    }
}

enum MLXWhisperError: LocalizedError {
    case notInstalled
    case ffmpegMissing
    case processFailed(status: Int, stderr: String)
    case outputMissing(expected: URL)
    case decodingFailed(underlying: Error)
    case silenceGenerationFailed

    var errorDescription: String? {
        switch self {
        case .notInstalled:
            return "mlx_whisper isn't on PATH. Install with `pip install mlx-whisper` and reopen Settings."
        case .ffmpegMissing:
            return "ffmpeg is required by mlx_whisper but wasn't found on PATH. Install with `brew install ffmpeg`."
        case .processFailed(let status, let stderr):
            return "mlx_whisper exited with status \(status): \(stderr.prefix(300))"
        case .outputMissing(let url):
            return "mlx_whisper finished but no JSON output was found at \(url.path(percentEncoded: false))."
        case .decodingFailed(let underlying):
            return "Couldn't decode mlx_whisper JSON: \(underlying.localizedDescription)"
        case .silenceGenerationFailed:
            return "Couldn't generate silent warm-up audio."
        }
    }
}
