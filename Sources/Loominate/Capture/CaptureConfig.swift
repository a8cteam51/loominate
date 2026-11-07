import CoreMedia
import CoreVideo
import ScreenCaptureKit

/// Everything the stream needs, derived once from preferences and the chosen source.
struct CaptureConfig {
    let filter: SCContentFilter
    let isWindow: Bool
    let width: Int
    let height: Int
    let fps: Int
    let showsCursor: Bool
    let systemAudio: Bool
    let microphone: Bool
    let microphoneDeviceID: String?
    /// True when camera frames are composited onto screen frames (needs BGRA).
    let compositeBubble: Bool

    var pixelFormat: OSType {
        compositeBubble ? kCVPixelFormatType_32BGRA : kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
    }

    init(filter: SCContentFilter,
         isWindow: Bool,
         prefs: Preferences,
         systemAudio: Bool,
         microphone: Bool,
         microphoneDeviceID: String?,
         compositeBubble: Bool) {
        self.filter = filter
        self.isWindow = isWindow
        self.fps = prefs.frameRate.rawValue
        self.showsCursor = prefs.showsCursor
        self.systemAudio = systemAudio
        self.microphone = microphone
        self.microphoneDeviceID = microphoneDeviceID
        self.compositeBubble = compositeBubble

        let rect = filter.contentRect
        let scale: CGFloat = prefs.scale == .two ? CGFloat(filter.pointPixelScale) : 1
        var w = Int((rect.width * scale).rounded(.down))
        var h = Int((rect.height * scale).rounded(.down))
        w -= w % 2
        h -= h % 2
        self.width = max(w, 2)
        self.height = max(h, 2)
    }

    func makeStreamConfiguration() -> SCStreamConfiguration {
        let c = SCStreamConfiguration()
        c.width = width
        c.height = height
        c.scalesToFit = true
        c.preservesAspectRatio = true
        c.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(fps))
        c.queueDepth = 6
        c.showsCursor = showsCursor
        c.captureResolution = .best
        c.pixelFormat = pixelFormat
        c.colorSpaceName = CGColorSpace.sRGB
        if isWindow {
            c.ignoreShadowsSingleWindow = true
            c.includeChildWindows = true
            c.shouldBeOpaque = true
            c.backgroundColor = CGColor.black
        }
        c.capturesAudio = systemAudio
        c.excludesCurrentProcessAudio = true
        c.sampleRate = 48_000
        c.channelCount = 2
        c.captureMicrophone = microphone
        c.microphoneCaptureDeviceID = microphoneDeviceID
        return c
    }
}
