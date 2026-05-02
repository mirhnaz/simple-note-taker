import AVFAudio
import Foundation
import os

private let log = Logger(subsystem: "com.mir.SimpleNoteTaker", category: "mic")

final class MicCapture {
    let outputURL: URL
    private let engine: AVAudioEngine
    private var audioFile: AVAudioFile?

    static func start(outputURL: URL, transcriber: LiveTranscriber? = nil) throws -> MicCapture {
        let engine = AVAudioEngine()
        let inputFormat = engine.inputNode.outputFormat(forBus: 0)

        let fileSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: inputFormat.sampleRate,
            AVNumberOfChannelsKey: Int(inputFormat.channelCount),
            AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue
        ]

        let file = try AVAudioFile(
            forWriting: outputURL,
            settings: fileSettings,
            commonFormat: inputFormat.commonFormat,
            interleaved: inputFormat.isInterleaved
        )

        let analyzerFormat: AVAudioFormat? = transcriber?.analyzerFormat
        let converter: AVAudioConverter? = analyzerFormat.flatMap { AVAudioConverter(from: inputFormat, to: $0) }
        let feeder = TranscriberFeeder(transcriber: transcriber, converter: converter, targetFormat: analyzerFormat)

        let capture = MicCapture(outputURL: outputURL, engine: engine, audioFile: file)

        engine.inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak capture] buffer, _ in
            try? capture?.audioFile?.write(from: buffer)
            feeder.feed(buffer)
        }

        try engine.start()
        log.info("mic capture started: \(outputURL.lastPathComponent, privacy: .public)")
        return capture
    }

    private init(outputURL: URL, engine: AVAudioEngine, audioFile: AVAudioFile) {
        self.outputURL = outputURL
        self.engine = engine
        self.audioFile = audioFile
    }

    func stop() {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        // Release the AVAudioFile so the .m4a moov atom is written immediately
        // rather than whenever this object eventually deallocates.
        audioFile = nil
        log.info("mic capture stopped: \(self.outputURL.lastPathComponent, privacy: .public)")
    }
}

private final class TranscriberFeeder: @unchecked Sendable {
    private let transcriber: LiveTranscriber?
    private let converter: AVAudioConverter?
    private let targetFormat: AVAudioFormat?

    init(transcriber: LiveTranscriber?, converter: AVAudioConverter?, targetFormat: AVAudioFormat?) {
        self.transcriber = transcriber
        self.converter = converter
        self.targetFormat = targetFormat
    }

    func feed(_ buffer: AVAudioPCMBuffer) {
        guard let transcriber else { return }
        guard let converter, let targetFormat else {
            transcriber.feed(buffer)
            return
        }
        let ratio = targetFormat.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio + 1024)
        guard let outBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: capacity) else { return }
        var consumed = false
        var convertError: NSError?
        let status = converter.convert(to: outBuffer, error: &convertError) { _, status in
            if consumed {
                status.pointee = .noDataNow
                return nil
            }
            consumed = true
            status.pointee = .haveData
            return buffer
        }
        if status == .error || convertError != nil { return }
        guard outBuffer.frameLength > 0 else { return }
        transcriber.feed(outBuffer)
    }
}
