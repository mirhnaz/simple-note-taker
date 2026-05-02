import AVFoundation
import CoreMedia
import Foundation
import ScreenCaptureKit

enum SystemAudioCaptureError: LocalizedError {
    case noDisplayAvailable
    case permissionDenied(underlying: Error)

    var errorDescription: String? {
        switch self {
        case .noDisplayAvailable:
            return "No display is available for system audio capture."
        case .permissionDenied:
            return "Screen Recording permission is required to capture meeting audio (other participants). Mic-only recording will continue. Enable it in System Settings → Privacy & Security → Screen & System Audio Recording."
        }
    }
}

final class SystemAudioCapture {
    let outputURL: URL

    private let stream: SCStream
    private let writer: AVAssetWriter
    private let writerInput: AVAssetWriterInput
    private let outputHandler: SystemAudioOutputHandler

    static func start(outputURL: URL) async throws -> SystemAudioCapture {
        let writer = try AVAssetWriter(outputURL: outputURL, fileType: .m4a)
        let audioSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 48000,
            AVNumberOfChannelsKey: 2,
            AVEncoderBitRateKey: 96000
        ]
        let input = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
        input.expectsMediaDataInRealTime = true
        writer.add(input)

        let content: SCShareableContent
        do {
            content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        } catch {
            throw SystemAudioCaptureError.permissionDenied(underlying: error)
        }
        guard let display = content.displays.first else {
            throw SystemAudioCaptureError.noDisplayAvailable
        }

        let filter = SCContentFilter(display: display, excludingWindows: [])
        let config = SCStreamConfiguration()
        config.capturesAudio = true
        config.excludesCurrentProcessAudio = true
        config.width = 2
        config.height = 2
        config.minimumFrameInterval = CMTime(value: 1, timescale: 1)

        let handler = SystemAudioOutputHandler(writer: writer, input: input)
        let videoSink = SystemVideoSink()
        let stream = SCStream(filter: filter, configuration: config, delegate: nil)
        try stream.addStreamOutput(handler, type: .audio, sampleHandlerQueue: handler.queue)
        // SCK has no audio-only mode; without a video output, every frame logs
        // "stream output NOT found. Dropping frame". A noop sink silences it.
        try stream.addStreamOutput(videoSink, type: .screen, sampleHandlerQueue: videoSink.queue)

        try await stream.startCapture()

        return SystemAudioCapture(outputURL: outputURL, stream: stream, writer: writer, writerInput: input, outputHandler: handler)
    }

    private init(outputURL: URL, stream: SCStream, writer: AVAssetWriter, writerInput: AVAssetWriterInput, outputHandler: SystemAudioOutputHandler) {
        self.outputURL = outputURL
        self.stream = stream
        self.writer = writer
        self.writerInput = writerInput
        self.outputHandler = outputHandler
    }

    func stop() async {
        try? await stream.stopCapture()
        writerInput.markAsFinished()
        if writer.status == .writing {
            await writer.finishWriting()
        }
    }
}

private final class SystemVideoSink: NSObject, SCStreamOutput, @unchecked Sendable {
    let queue = DispatchQueue(label: "system-video-sink")

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        // discard
    }
}

private final class SystemAudioOutputHandler: NSObject, SCStreamOutput, @unchecked Sendable {
    let queue = DispatchQueue(label: "system-audio-output")
    private let writer: AVAssetWriter
    private let input: AVAssetWriterInput
    private var sessionStarted = false

    init(writer: AVAssetWriter, input: AVAssetWriterInput) {
        self.writer = writer
        self.input = input
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio, sampleBuffer.isValid else { return }

        if !sessionStarted {
            guard writer.startWriting() else { return }
            writer.startSession(atSourceTime: sampleBuffer.presentationTimeStamp)
            sessionStarted = true
        }

        if input.isReadyForMoreMediaData {
            input.append(sampleBuffer)
        }
    }
}
