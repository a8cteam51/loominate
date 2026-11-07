import AppKit
import ScreenCaptureKit

struct DisplayInfo: Identifiable, Hashable {
    let id: CGDirectDisplayID
    let name: String
    let width: Int
    let height: Int
    let isMain: Bool
    var label: String { "\(name) (\(width)×\(height))" }
}

struct WindowInfo: Identifiable, Hashable {
    let id: CGWindowID
    let title: String
    let appName: String
    let bundleID: String?
    var label: String { appName.isEmpty ? title : "\(appName) — \(title)" }
}

enum CaptureSource: Hashable {
    case display(CGDirectDisplayID)
    case window(CGWindowID)

    var isWindow: Bool {
        if case .window = self { return true }
        return false
    }
}

/// One fetch of what ScreenCaptureKit can see, plus our own process for exclusion.
struct ShareableSnapshot {
    let content: SCShareableContent
    let displays: [DisplayInfo]
    let windows: [WindowInfo]
    let ownApplication: SCRunningApplication?

    func display(_ id: CGDirectDisplayID) -> SCDisplay? {
        content.displays.first { $0.displayID == id }
    }

    func window(_ id: CGWindowID) -> SCWindow? {
        content.windows.first { $0.windowID == id }
    }
}

enum ContentError: LocalizedError {
    case sourceUnavailable
    case screenRecordingDenied

    var errorDescription: String? {
        switch self {
        case .sourceUnavailable: return "The selected screen or window is no longer available."
        case .screenRecordingDenied: return "Screen Recording permission is required. Grant it in System Settings and relaunch Loominate."
        }
    }
}

enum ContentEnumerator {
    static func snapshot() async throws -> ShareableSnapshot {
        let content: SCShareableContent
        do {
            content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        } catch {
            if !Permissions.screenRecordingGranted() { throw ContentError.screenRecordingDenied }
            throw error
        }
        let pid = ProcessInfo.processInfo.processIdentifier
        let own = content.applications.first { $0.processID == pid }
        let ownWindows = content.windows.filter { $0.owningApplication?.processID == pid }.count
        Log.note("shareable content: own app \(own == nil ? "NOT found" : "found") in \(content.applications.count) apps; \(ownWindows) own windows on screen")
        let mainID = CGMainDisplayID()
        let displays = content.displays.enumerated().map { index, display in
            DisplayInfo(id: display.displayID,
                        name: displayName(display, index: index),
                        width: display.width,
                        height: display.height,
                        isMain: display.displayID == mainID)
        }
        let windows = content.windows
            .filter { window in
                window.windowLayer == 0
                    && window.isOnScreen
                    && window.frame.width >= 120
                    && window.frame.height >= 80
                    && !(window.title ?? "").isEmpty
                    && window.owningApplication?.processID != pid
            }
            .map { window in
                WindowInfo(id: window.windowID,
                           title: window.title ?? "",
                           appName: window.owningApplication?.applicationName ?? "",
                           bundleID: window.owningApplication?.bundleIdentifier)
            }
        return ShareableSnapshot(content: content, displays: displays, windows: windows, ownApplication: own)
    }

    /// Display captures exclude every window of this app (HUD, preview, countdown, panel).
    static func makeFilter(for source: CaptureSource, in snapshot: ShareableSnapshot) throws -> SCContentFilter {
        switch source {
        case .display(let id):
            guard let display = snapshot.display(id) else { throw ContentError.sourceUnavailable }
            let excluded = snapshot.ownApplication.map { [$0] } ?? []
            return SCContentFilter(display: display, excludingApplications: excluded, exceptingWindows: [])
        case .window(let id):
            guard let window = snapshot.window(id) else { throw ContentError.sourceUnavailable }
            return SCContentFilter(desktopIndependentWindow: window)
        }
    }

    private static func displayName(_ display: SCDisplay, index: Int) -> String {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        if let screen = NSScreen.screens.first(where: {
            ($0.deviceDescription[key] as? NSNumber)?.uint32Value == display.displayID
        }) {
            return screen.localizedName
        }
        return "Display \(index + 1)"
    }
}
