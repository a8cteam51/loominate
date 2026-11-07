import Foundation

enum QualityPreset: String, CaseIterable, Codable, Identifiable {
    case low, medium, high
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
    /// Bits per pixel per frame fed into the bitrate heuristic.
    var bitsPerPixel: Double {
        switch self {
        case .low: return 0.025
        case .medium: return 0.04
        case .high: return 0.07
        }
    }
}

enum VideoCodecChoice: String, CaseIterable, Codable, Identifiable {
    case h264, hevc
    var id: String { rawValue }
    var label: String {
        switch self {
        case .h264: return "H.264 (plays everywhere)"
        case .hevc: return "HEVC (smaller, needs newer players)"
        }
    }
}

enum CaptureScale: Int, CaseIterable, Codable, Identifiable {
    case one = 1, two = 2
    var id: Int { rawValue }
    var label: String { self == .one ? "1x (smaller files)" : "2x Retina (sharper text)" }
}

enum FrameRate: Int, CaseIterable, Codable, Identifiable {
    case fps15 = 15, fps30 = 30, fps60 = 60
    var id: Int { rawValue }
    var label: String { "\(rawValue) fps" }
}

enum BubbleSize: String, CaseIterable, Codable, Identifiable {
    case small, medium, large
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
    /// Bubble diameter as a fraction of the output height.
    var fraction: Double {
        switch self {
        case .small: return 0.14
        case .medium: return 0.18
        case .large: return 0.24
        }
    }
}

enum BubbleCorner: String, CaseIterable, Codable, Identifiable {
    case bottomLeft, bottomRight, topLeft, topRight
    var id: String { rawValue }
    var label: String {
        switch self {
        case .bottomLeft: return "Bottom left"
        case .bottomRight: return "Bottom right"
        case .topLeft: return "Top left"
        case .topRight: return "Top right"
        }
    }
}

struct Preferences: Codable, Equatable {
    var quality: QualityPreset = .medium
    var frameRate: FrameRate = .fps30
    var scale: CaptureScale = .one
    var codec: VideoCodecChoice = .h264
    var bubbleSize: BubbleSize = .medium
    var bubbleCorner: BubbleCorner = .bottomLeft
    var countdownSeconds: Int = 3
    var showsCursor: Bool = true
    var outputFolderPath: String = Preferences.defaultOutputFolder.path
    var revealInFinderAfterSave: Bool = true
    var cameraEnabled: Bool = false
    var microphoneEnabled: Bool = true
    var systemAudioEnabled: Bool = true
    /// nil means "the default camera".
    var cameraDeviceID: String? = nil
    /// nil means "the system default input", which ScreenCaptureKit follows live.
    var microphoneDeviceID: String? = nil

    // Upload
    /// Off by default: outtakes should never leave the Mac unless the user asks.
    var autoUpload: Bool = false
    var titlePrefix: String = ""
    var copyLinkAfterUpload: Bool = true
    var notifyWhenUploaded: Bool = true
    var deleteLocalAfterUpload: Bool = false

    // Updates
    var checkForUpdatesAutomatically: Bool = true

    static let defaultOutputFolder: URL = {
        let movies = FileManager.default.urls(for: .moviesDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Movies")
        return movies.appendingPathComponent("Loominate", isDirectory: true)
    }()

    var outputFolder: URL { URL(fileURLWithPath: outputFolderPath, isDirectory: true) }

    enum CodingKeys: String, CodingKey {
        case quality, frameRate, scale, codec, bubbleSize, bubbleCorner, countdownSeconds, showsCursor
        case outputFolderPath, revealInFinderAfterSave, cameraEnabled, microphoneEnabled, systemAudioEnabled
        case cameraDeviceID, microphoneDeviceID
        case autoUpload = "autoUploadRecordings"
        case titlePrefix, copyLinkAfterUpload, notifyWhenUploaded, deleteLocalAfterUpload
        case checkForUpdatesAutomatically
    }

    init() {}

    // Decode field by field so preferences saved by an older build still load.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Preferences()
        quality = try c.decodeIfPresent(QualityPreset.self, forKey: .quality) ?? d.quality
        frameRate = try c.decodeIfPresent(FrameRate.self, forKey: .frameRate) ?? d.frameRate
        scale = try c.decodeIfPresent(CaptureScale.self, forKey: .scale) ?? d.scale
        codec = try c.decodeIfPresent(VideoCodecChoice.self, forKey: .codec) ?? d.codec
        bubbleSize = try c.decodeIfPresent(BubbleSize.self, forKey: .bubbleSize) ?? d.bubbleSize
        bubbleCorner = try c.decodeIfPresent(BubbleCorner.self, forKey: .bubbleCorner) ?? d.bubbleCorner
        countdownSeconds = try c.decodeIfPresent(Int.self, forKey: .countdownSeconds) ?? d.countdownSeconds
        showsCursor = try c.decodeIfPresent(Bool.self, forKey: .showsCursor) ?? d.showsCursor
        outputFolderPath = try c.decodeIfPresent(String.self, forKey: .outputFolderPath) ?? d.outputFolderPath
        revealInFinderAfterSave = try c.decodeIfPresent(Bool.self, forKey: .revealInFinderAfterSave) ?? d.revealInFinderAfterSave
        cameraEnabled = try c.decodeIfPresent(Bool.self, forKey: .cameraEnabled) ?? d.cameraEnabled
        microphoneEnabled = try c.decodeIfPresent(Bool.self, forKey: .microphoneEnabled) ?? d.microphoneEnabled
        systemAudioEnabled = try c.decodeIfPresent(Bool.self, forKey: .systemAudioEnabled) ?? d.systemAudioEnabled
        cameraDeviceID = try c.decodeIfPresent(String.self, forKey: .cameraDeviceID)
        microphoneDeviceID = try c.decodeIfPresent(String.self, forKey: .microphoneDeviceID)
        autoUpload = try c.decodeIfPresent(Bool.self, forKey: .autoUpload) ?? d.autoUpload
        titlePrefix = try c.decodeIfPresent(String.self, forKey: .titlePrefix) ?? d.titlePrefix
        copyLinkAfterUpload = try c.decodeIfPresent(Bool.self, forKey: .copyLinkAfterUpload) ?? d.copyLinkAfterUpload
        notifyWhenUploaded = try c.decodeIfPresent(Bool.self, forKey: .notifyWhenUploaded) ?? d.notifyWhenUploaded
        deleteLocalAfterUpload = try c.decodeIfPresent(Bool.self, forKey: .deleteLocalAfterUpload) ?? d.deleteLocalAfterUpload
        checkForUpdatesAutomatically = try c.decodeIfPresent(Bool.self, forKey: .checkForUpdatesAutomatically) ?? d.checkForUpdatesAutomatically
    }

    private static let defaultsKey = "preferences.v1"

    static func load() -> Preferences {
        if let data = UserDefaults.standard.data(forKey: defaultsKey),
           let prefs = try? JSONDecoder().decode(Preferences.self, from: data) {
            return prefs
        }
        return Preferences()
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: Preferences.defaultsKey)
        }
    }

    /// Target average bitrate in bits per second for the given output size.
    func videoBitrate(width: Int, height: Int) -> Int {
        var bps = Double(width * height) * Double(frameRate.rawValue) * quality.bitsPerPixel
        if codec == .hevc { bps *= 0.6 }
        return Int(min(max(bps, 400_000), 40_000_000))
    }
}
