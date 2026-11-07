import AVFoundation
import CoreMedia

/// AVAssetWriter wrapper for the intermediate .mov: video plus up to two audio tracks.
/// All methods except `finish` must be called on the capture queue.
final class RecordingWriter {
    enum Track: Hashable, CaseIterable {
        case video, systemAudio, microphone
    }

    let url: URL
    private let writer: AVAssetWriter
    private let videoInput: AVAssetWriterInput
    private let adaptor: AVAssetWriterInputPixelBufferAdaptor
    private var audioInputs: [Track: AVAssetWriterInput] = [:]
    private var lastPTS: [Track: CMTime] = [:]
    private(set) var appended: [Track: Int] = [:]
    private(set) var dropped: [Track: Int] = [:]
    private(set) var sessionStart: CMTime?

    /// Audio tracks in the order they were added to the file (matters for the mixdown gains).
    private(set) var audioTrackOrder: [Track] = []

    var failure: Error? { writer.status == .failed ? writer.error : nil }

    init(url: URL,
         width: Int,
         height: Int,
         pixelFormat: OSType,
         videoSettings: [String: Any],
         wantsSystemAudio: Bool,
         systemAudioFormat: CMFormatDescription?,
         wantsMicrophone: Bool,
         microphoneFormat: CMFormatDescription?) throws {
        self.url = url
        writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        writer.movieFragmentInterval = CMTime(seconds: 3, preferredTimescale: 600)

        videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        videoInput.expectsMediaDataInRealTime = true
        adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: videoInput, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: pixelFormat,
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height,
        ])
        guard writer.canAdd(videoInput) else { throw RecordingError.cannotAddInput("video") }
        writer.add(videoInput)

        if wantsSystemAudio {
            audioInputs[.systemAudio] = try Self.makeAudioInput(format: systemAudioFormat, fallbackChannels: 2, writer: writer, name: "system audio")
            audioTrackOrder.append(.systemAudio)
        }
        if wantsMicrophone {
            audioInputs[.microphone] = try Self.makeAudioInput(format: microphoneFormat, fallbackChannels: 1, writer: writer, name: "microphone")
            audioTrackOrder.append(.microphone)
        }
    }

    private static func makeAudioInput(format: CMFormatDescription?, fallbackChannels: Int, writer: AVAssetWriter, name: String) throws -> AVAssetWriterInput {
        var channels = fallbackChannels
        if let asbd = format?.audioStreamBasicDescription {
            channels = Int(asbd.mChannelsPerFrame)
        }
        channels = min(max(channels, 1), 2)
        let input = AVAssetWriterInput(mediaType: .audio, outputSettings: CodecSettings.audio(channels: channels), sourceFormatHint: format)
        input.expectsMediaDataInRealTime = true
        guard writer.canAdd(input) else { throw RecordingError.cannotAddInput(name) }
        writer.add(input)
        Log.note("\(name) input: \(channels) ch, format hint=\(format != nil)")
        return input
    }

    func start(at time: CMTime) throws {
        guard writer.startWriting() else {
            throw writer.error ?? RecordingError.writerFailed("could not start writing")
        }
        writer.startSession(atSourceTime: time)
        sessionStart = time
    }

    @discardableResult
    func appendVideo(_ pixelBuffer: CVPixelBuffer, at pts: CMTime) -> Bool {
        guard let start = sessionStart, writer.status == .writing, pts >= start else { return false }
        if let last = lastPTS[.video], pts <= last {
            dropped[.video, default: 0] += 1
            return false
        }
        guard videoInput.isReadyForMoreMediaData else {
            dropped[.video, default: 0] += 1
            return false
        }
        guard adaptor.append(pixelBuffer, withPresentationTime: pts) else {
            dropped[.video, default: 0] += 1
            Log.writer.error("video append failed: \(self.writer.error?.localizedDescription ?? "unknown")")
            return false
        }
        lastPTS[.video] = pts
        appended[.video, default: 0] += 1
        return true
    }

    @discardableResult
    func appendAudio(_ sampleBuffer: CMSampleBuffer, track: Track) -> Bool {
        guard let input = audioInputs[track], let start = sessionStart, writer.status == .writing else { return false }
        let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        guard pts >= start else { return false }
        if let last = lastPTS[track], pts <= last {
            dropped[track, default: 0] += 1
            return false
        }
        guard input.isReadyForMoreMediaData else {
            dropped[track, default: 0] += 1
            return false
        }
        guard input.append(sampleBuffer) else {
            dropped[track, default: 0] += 1
            Log.writer.error("audio append failed (\(String(describing: track))): \(self.writer.error?.localizedDescription ?? "unknown")")
            return false
        }
        lastPTS[track] = pts
        appended[track, default: 0] += 1
        return true
    }

    func finish() async throws {
        if writer.status == .writing {
            videoInput.markAsFinished()
            for input in audioInputs.values { input.markAsFinished() }
            await writer.finishWriting()
        }
        Log.note("writer finished: appended=\(appended) dropped=\(dropped) status=\(writer.status.rawValue)")
        guard writer.status == .completed else {
            throw writer.error ?? RecordingError.writerFailed("status \(writer.status.rawValue)")
        }
    }

    func cancel() {
        if writer.status == .writing { writer.cancelWriting() }
    }
}
