import CoreMedia
import ScreenCaptureKit

/// Owns the SCStream and hands complete sample buffers to closures on `queue`.
final class ScreenCaptureSession: NSObject, SCStreamOutput, SCStreamDelegate {
    let queue = DispatchQueue(label: "com.automattic.loominate.capture")

    var onScreenFrame: ((CMSampleBuffer) -> Void)?
    var onSystemAudio: ((CMSampleBuffer) -> Void)?
    var onMicrophone: ((CMSampleBuffer) -> Void)?
    /// Called when the system ends the stream (display unplugged, user stop, error).
    var onStopped: ((Error) -> Void)?

    private var stream: SCStream?
    private var receivedTypes = Set<SCStreamOutputType>()

    func start(config: CaptureConfig) async throws {
        let stream = SCStream(filter: config.filter, configuration: config.makeStreamConfiguration(), delegate: self)
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: queue)
        if config.systemAudio {
            try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: queue)
        }
        if config.microphone {
            try stream.addStreamOutput(self, type: .microphone, sampleHandlerQueue: queue)
        }
        try await stream.startCapture()
        self.stream = stream
        Log.note("stream started \(config.width)x\(config.height)@\(config.fps) window=\(config.isWindow) systemAudio=\(config.systemAudio) mic=\(config.microphone) micDevice=\(config.microphoneDeviceID ?? "default") bubble=\(config.compositeBubble)")
    }

    func stop() async {
        guard let stream else { return }
        self.stream = nil
        do {
            try await stream.stopCapture()
        } catch {
            Log.capture.warning("stopCapture: \(error.localizedDescription)")
        }
    }

    // MARK: SCStreamOutput

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard sampleBuffer.isValid else { return }
        if !receivedTypes.contains(type) {
            receivedTypes.insert(type)
            Log.note("first buffer of type \(type.rawValue) (0=screen 1=system audio 2=mic)")
        }
        switch type {
        case .screen:
            guard Self.isCompleteFrame(sampleBuffer), CMSampleBufferGetImageBuffer(sampleBuffer) != nil else { return }
            onScreenFrame?(sampleBuffer)
        case .audio:
            onSystemAudio?(sampleBuffer)
        case .microphone:
            onMicrophone?(sampleBuffer)
        @unknown default:
            break
        }
    }

    private static func isCompleteFrame(_ sampleBuffer: CMSampleBuffer) -> Bool {
        guard let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
              let info = attachments.first,
              let rawStatus = info[.status] as? Int,
              let status = SCFrameStatus(rawValue: rawStatus) else {
            return false
        }
        return status == .complete
    }

    // MARK: SCStreamDelegate

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        Log.note("stream stopped by system: \(error.localizedDescription)")
        self.stream = nil
        onStopped?(error)
    }
}
