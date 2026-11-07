import AVFoundation
import Foundation
import Observation

struct MediaDevice: Identifiable, Hashable {
    let id: String   // AVCaptureDevice.uniqueID
    let name: String
}

/// Cameras and microphones attached to this Mac, refreshed on hot-plug.
@MainActor @Observable
final class DeviceCatalog {
    private(set) var cameras: [MediaDevice] = []
    private(set) var microphones: [MediaDevice] = []
    private(set) var defaultCameraID: String?
    private(set) var defaultMicrophoneID: String?

    @ObservationIgnored private var observers: [NSObjectProtocol] = []

    init() {
        refresh()
        for name in [AVCaptureDevice.wasConnectedNotification, AVCaptureDevice.wasDisconnectedNotification] {
            let token = NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.refresh() }
            }
            observers.append(token)
        }
    }

    func refresh() {
        cameras = Self.cameraDevices().map { MediaDevice(id: $0.uniqueID, name: $0.localizedName) }
        defaultCameraID = Self.cameraDevice(id: nil)?.uniqueID
        microphones = Self.microphoneDevices().map { MediaDevice(id: $0.uniqueID, name: $0.localizedName) }
        defaultMicrophoneID = Self.microphoneDevice(id: nil)?.uniqueID
        Log.devices.debug("cameras=\(self.cameras.map(\.name)) mics=\(self.microphones.map(\.name))")
    }

    nonisolated static func cameraDevices() -> [AVCaptureDevice] {
        AVCaptureDevice.DiscoverySession(deviceTypes: DeviceTypes.cameras, mediaType: .video, position: .unspecified).devices
    }

    nonisolated static func microphoneDevices() -> [AVCaptureDevice] {
        AVCaptureDevice.DiscoverySession(deviceTypes: DeviceTypes.microphones, mediaType: .audio, position: .unspecified).devices
    }

    /// Resolves a stored camera id, falling back to the preferred/default camera.
    nonisolated static func cameraDevice(id: String?) -> AVCaptureDevice? {
        if let id, let device = AVCaptureDevice(uniqueID: id), device.hasMediaType(.video) {
            return device
        }
        return AVCaptureDevice.systemPreferredCamera ?? AVCaptureDevice.default(for: .video)
    }

    /// Resolves a stored microphone id, falling back to the system default input.
    nonisolated static func microphoneDevice(id: String?) -> AVCaptureDevice? {
        if let id, let device = AVCaptureDevice(uniqueID: id), device.hasMediaType(.audio) {
            return device
        }
        return AVCaptureDevice.default(for: .audio)
    }

    /// True when the stored id still names an attached device.
    func isAttachedMicrophone(_ id: String?) -> Bool {
        guard let id else { return true }
        return microphones.contains { $0.id == id }
    }

    func isAttachedCamera(_ id: String?) -> Bool {
        guard let id else { return true }
        return cameras.contains { $0.id == id }
    }
}

private enum DeviceTypes {
    static let cameras: [AVCaptureDevice.DeviceType] = [.builtInWideAngleCamera, .continuityCamera, .external]
    static let microphones: [AVCaptureDevice.DeviceType] = [.microphone, .external]
}
