import AVFoundation
import CoreMedia
import ScreenCaptureKit

struct RecordingRequest {
    var source: CaptureSource
    var snapshot: ShareableSnapshot
    var prefs: Preferences
    var systemAudio: Bool
    var microphone: Bool
    /// nil follows the system default input.
    var microphoneDeviceID: String?
    /// Non-nil composites the camera bubble into the recording.
    var cameraSource: CameraFrameSource?
    /// Menu bar / Dock areas of the captured display, in points; zero for window captures.
    var bubbleInsets: BubbleInsets = .zero
}

/// Orchestrates one recording: warm-up, writer session at T0, pacing, stop, mixdown.
final class RecordingSession {
    enum State { case idle, warmingUp, recording, stopping, finished }

    struct Summary {
        let url: URL
        let duration: TimeInterval
        let appended: [RecordingWriter.Track: Int]
        let dropped: [RecordingWriter.Track: Int]
    }

    private let capture = ScreenCaptureSession()
    private var queue: DispatchQueue { capture.queue }

    private var request: RecordingRequest?
    private var config: CaptureConfig?
    private var writer: RecordingWriter?
    private var compositor: BubbleCompositor?
    private var pacer: FramePacer?
    private var tempURL: URL?

    // Capture-queue state.
    private var state: State = .idle
    private var latestScreen: CMSampleBuffer?
    private var lastAppended: CVPixelBuffer?
    private var lastAppendedPTS: CMTime = .invalid
    private var startTime: CMTime?
    private var systemAudioFormat: CMFormatDescription?
    private var microphoneFormat: CMFormatDescription?

    /// Fired on an arbitrary queue when the system ends the stream mid-recording.
    var onStreamStopped: ((Error) -> Void)?

    var isRecording: Bool { queue.sync { state == .recording } }

    // MARK: Lifecycle

    /// Builds the filter and starts the stream so audio formats and a first frame arrive before T0.
    func prepare(_ request: RecordingRequest) async throws {
        let filter = try ContentEnumerator.makeFilter(for: request.source, in: request.snapshot)
        let config = CaptureConfig(filter: filter,
                                   isWindow: request.source.isWindow,
                                   prefs: request.prefs,
                                   systemAudio: request.systemAudio,
                                   microphone: request.microphone,
                                   microphoneDeviceID: request.microphoneDeviceID,
                                   compositeBubble: request.cameraSource != nil)
        self.request = request
        self.config = config

        capture.onScreenFrame = { [weak self] buffer in self?.handleScreen(buffer) }
        capture.onSystemAudio = { [weak self] buffer in self?.handleAudio(buffer, track: .systemAudio) }
        capture.onMicrophone = { [weak self] buffer in self?.handleAudio(buffer, track: .microphone) }
        capture.onStopped = { [weak self] error in
            guard let self else { return }
            let wasRecording = self.queue.sync { self.state == .recording || self.state == .warmingUp }
            if wasRecording { self.onStreamStopped?(error) }
        }
        queue.sync { state = .warmingUp }
        try await capture.start(config: config)
    }

    /// Starts the writer session at the current host time. Call after the countdown.
    func beginRecording(tempURL: URL) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async {
                do {
                    try self.beginOnQueue(tempURL: tempURL)
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func beginOnQueue(tempURL: URL) throws {
        guard let request, let config, state == .warmingUp else { throw RecordingError.notPrepared }
        let t0 = CMClockGetTime(CMClockGetHostTimeClock())
        let settings = CodecSettings.video(prefs: request.prefs, width: config.width, height: config.height)
        let writer = try RecordingWriter(url: tempURL,
                                         width: config.width,
                                         height: config.height,
                                         pixelFormat: config.pixelFormat,
                                         videoSettings: settings,
                                         wantsSystemAudio: config.systemAudio,
                                         systemAudioFormat: systemAudioFormat,
                                         wantsMicrophone: config.microphone,
                                         microphoneFormat: microphoneFormat)
        if config.compositeBubble {
            let pointScale = config.filter.contentRect.width > 0 ? CGFloat(config.width) / config.filter.contentRect.width : 1
            compositor = try BubbleCompositor(width: config.width, height: config.height,
                                              size: request.prefs.bubbleSize, corner: request.prefs.bubbleCorner,
                                              insets: request.bubbleInsets.scaled(by: pointScale))
        }
        try writer.start(at: t0)
        self.writer = writer
        self.tempURL = tempURL
        startTime = t0
        state = .recording
        Log.note("recording started; audio formats known: system=\(systemAudioFormat != nil) mic=\(microphoneFormat != nil)")

        // Put the frame we already have at T0 so a static screen does not start black.
        if let buffer = latestScreen, let pixels = CMSampleBufferGetImageBuffer(buffer) {
            appendFrame(pixels, at: t0)
        }
        let pacer = FramePacer(queue: queue, fps: config.fps) { [weak self] in self?.tick() }
        self.pacer = pacer
        pacer.start()
    }

    /// Ends capture, finalizes the intermediate, and produces the final .mp4.
    func stop() async throws -> Summary {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            queue.async {
                self.state = .stopping
                self.pacer?.stop()
                self.pacer = nil
                continuation.resume()
            }
        }
        await capture.stop()
        queue.sync { }   // drain any callback already in flight

        guard let writer, let tempURL, let startTime else {
            throw RecordingError.notPrepared
        }
        let duration = CMTimeSubtract(CMClockGetTime(CMClockGetHostTimeClock()), startTime).seconds
        try await writer.finish()

        let finalURL = tempURL.deletingPathExtension().appendingPathExtension("mp4")
        let gains: [Float] = writer.audioTrackOrder.map { $0 == .microphone ? 1.0 : 0.8 }
        try await Mixdown.run(input: tempURL, output: finalURL, gains: gains)
        try? FileManager.default.removeItem(at: tempURL)

        queue.sync { state = .finished }
        latestScreen = nil
        lastAppended = nil
        return Summary(url: finalURL, duration: duration, appended: writer.appended, dropped: writer.dropped)
    }

    /// Tears down a prepared-but-not-started session (countdown cancelled).
    func cancel() async {
        queue.sync {
            state = .idle
            pacer?.stop()
            pacer = nil
        }
        await capture.stop()
        writer?.cancel()
        if let tempURL { try? FileManager.default.removeItem(at: tempURL) }
        writer = nil
    }

    // MARK: Capture-queue handlers

    private func handleScreen(_ buffer: CMSampleBuffer) {
        latestScreen = buffer
        guard state == .recording, let config, !config.compositeBubble,
              let pixels = CMSampleBufferGetImageBuffer(buffer) else { return }
        appendFrame(pixels, at: CMSampleBufferGetPresentationTimeStamp(buffer))
    }

    private func handleAudio(_ buffer: CMSampleBuffer, track: RecordingWriter.Track) {
        if track == .systemAudio, systemAudioFormat == nil {
            systemAudioFormat = CMSampleBufferGetFormatDescription(buffer)
        } else if track == .microphone, microphoneFormat == nil {
            microphoneFormat = CMSampleBufferGetFormatDescription(buffer)
        }
        guard state == .recording else { return }
        writer?.appendAudio(buffer, track: track)
    }

    private func appendFrame(_ screen: CVPixelBuffer, at pts: CMTime) {
        let output: CVPixelBuffer
        if let compositor {
            guard let composed = compositor.compose(screen: screen, camera: request?.cameraSource?.latestFrame) else { return }
            output = composed
        } else {
            output = screen
        }
        if writer?.appendVideo(output, at: pts) == true {
            lastAppended = output
            lastAppendedPTS = pts
        }
    }

    private func tick() {
        guard state == .recording, let config else { return }
        let now = CMClockGetTime(CMClockGetHostTimeClock())
        if config.compositeBubble {
            guard let buffer = latestScreen, let pixels = CMSampleBufferGetImageBuffer(buffer) else { return }
            appendFrame(pixels, at: now)
        } else if lastAppendedPTS.isValid, let last = lastAppended,
                  CMTimeSubtract(now, lastAppendedPTS).seconds >= 1.0 {
            // Heartbeat: keep the video track alive through static stretches.
            if writer?.appendVideo(last, at: now) == true {
                lastAppendedPTS = now
            }
        }
    }
}
