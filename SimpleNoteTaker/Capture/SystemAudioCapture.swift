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

    static func start(outputURL: URL, transcriber: LiveTranscriber? = nil) async throws -> SystemAudioCapture {
        let writer = try AVAssetWriter(outputURL: outputURL, fileType: .m4a)
        // Write a movie fragment every few seconds so that if the app crashes
        // before finishWriting() runs, the file on disk is still a valid,
        // playable fragmented mp4 up to the last fragment — recoverable on the
        // next launch. Without this, an unfinalized AVAssetWriter output has no
        // moov atom and is unreadable.
        writer.movieFragmentInterval = CMTime(value: 5, timescale: 1)
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

        let handler = SystemAudioOutputHandler(writer: writer, input: input, transcriber: transcriber)
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
    private let transcriber: LiveTranscriber?
    private let targetFormat: AVAudioFormat?
    private var sessionStarted = false
    private var converter: AVAudioConverter?
    private var converterSourceFormat: AVAudioFormat?

    init(writer: AVAssetWriter, input: AVAssetWriterInput, transcriber: LiveTranscriber?) {
        self.writer = writer
        self.input = input
        self.transcriber = transcriber
        self.targetFormat = transcriber?.analyzerFormat
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

        feedTranscriber(sampleBuffer)
    }

    /// Converts the captured CMSampleBuffer to the analyzer's PCM format and
    /// feeds the live transcriber, so the menu bar shows other participants'
    /// speech in real time. Display-only: the final transcript is still a
    /// fresh pass over the recorded file in RecordingSession.stop().
    private func feedTranscriber(_ sampleBuffer: CMSampleBuffer) {
        guard let transcriber, let targetFormat else { return }
        guard let pcm = Self.pcmBuffer(from: sampleBuffer) else { return }

        // Build (and cache) a converter from the source format to the
        // analyzer format. SCStream audio is typically 48kHz stereo Float32;
        // the analyzer wants its own preferred format.
        if converter == nil || converterSourceFormat != pcm.format {
            converter = AVAudioConverter(from: pcm.format, to: targetFormat)
            converterSourceFormat = pcm.format
        }
        guard let converter else { return }

        let ratio = targetFormat.sampleRate / pcm.format.sampleRate
        let capacity = AVAudioFrameCount(Double(pcm.frameLength) * ratio + 1024)
        guard let outBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: capacity) else { return }
        var consumed = false
        var convertError: NSError?
        let status = converter.convert(to: outBuffer, error: &convertError) { _, statusPtr in
            if consumed {
                statusPtr.pointee = .noDataNow
                return nil
            }
            consumed = true
            statusPtr.pointee = .haveData
            return pcm
        }
        if status == .error || convertError != nil { return }
        guard outBuffer.frameLength > 0 else { return }
        transcriber.feed(outBuffer)
    }

    /// Wraps a CMSampleBuffer's audio samples in an AVAudioPCMBuffer without
    /// re-encoding. Returns nil if the buffer has no usable audio format.
    private static func pcmBuffer(from sampleBuffer: CMSampleBuffer) -> AVAudioPCMBuffer? {
        guard let formatDesc = CMSampleBufferGetFormatDescription(sampleBuffer),
              let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(formatDesc) else {
            return nil
        }
        let format = AVAudioFormat(streamDescription: asbd)
        guard let format else { return nil }
        let frameCount = AVAudioFrameCount(CMSampleBufferGetNumSamples(sampleBuffer))
        guard frameCount > 0,
              let pcm = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            return nil
        }
        pcm.frameLength = frameCount
        let status = CMSampleBufferCopyPCMDataIntoAudioBufferList(
            sampleBuffer,
            at: 0,
            frameCount: Int32(frameCount),
            into: pcm.mutableAudioBufferList
        )
        return status == noErr ? pcm : nil
    }
}
