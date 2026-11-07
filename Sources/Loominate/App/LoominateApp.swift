import AppKit
import SwiftUI

@main
struct LoominateApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    private let state: AppState

    init() {
        CLI.runIfRequested()
        state = AppState()
        AppDelegate.state = state
    }

    var body: some Scene {
        MenuBarExtra {
            MainPanelView(state: state)
        } label: {
            MenuBarLabel(state: state)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(state: state)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    static var state: AppState?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        ExceptionLog.install()
        AppDelegate.state?.updates.start()
        if let seconds = AutoRecord.secondsFromArguments(), let state = AppDelegate.state {
            AutoRecord.run(seconds: seconds, state: state)
        }
    }
}

/// Writes any uncaught Objective-C exception to stderr and ~/Library/Logs/Loominate/exceptions.log
/// before AppKit terminates the process, so crashes during layout are diagnosable.
enum ExceptionLog {
    static let fileURL: URL = {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/Loominate", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("exceptions.log")
    }()

    static func install() {
        NSSetUncaughtExceptionHandler { exception in
            ExceptionLog.record(exception)
        }
    }

    static func record(_ exception: NSException) {
        let text = """
        \(Date()) \(exception.name.rawValue): \(exception.reason ?? "no reason")
        \(exception.callStackSymbols.joined(separator: "\n"))

        """
        FileHandle.standardError.write(text.data(using: .utf8)!)
        if let handle = try? FileHandle(forWritingTo: fileURL) {
            handle.seekToEndOfFile()
            handle.write(text.data(using: .utf8)!)
            try? handle.close()
        } else {
            try? text.write(to: fileURL, atomically: true, encoding: .utf8)
        }
        Log.app.fault("uncaught exception: \(exception.name.rawValue): \(exception.reason ?? "")")
    }
}

/// `Loominate --auto-record <seconds>`: drives the real UI code path (countdown, HUD, menu bar
/// timer) with no clicks, for testing. Uses the saved preferences and the main display.
enum AutoRecord {
    static func secondsFromArguments() -> Double? {
        let args = CommandLine.arguments
        guard let index = args.firstIndex(of: "--auto-record"), index + 1 < args.count else { return nil }
        return Double(args[index + 1])
    }

    @MainActor
    static func run(seconds: Double, state: AppState) {
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1))
            await state.panelDidAppear()
            state.sourceKind = .display
            FileHandle.standardError.write("auto-record: permission=\(state.screenPermission) source=\(String(describing: state.selectedSource))\n".data(using: .utf8)!)
            await state.startRecording()
            FileHandle.standardError.write("auto-record: phase after start = \(state.phase)\n".data(using: .utf8)!)
            guard state.phase == .recording else { exit(2) }
            try? await Task.sleep(for: .seconds(seconds))
            await state.stopRecording()
            FileHandle.standardError.write("auto-record: phase after stop = \(state.phase)\n".data(using: .utf8)!)
            if CommandLine.arguments.contains("--upload"), case .saved = state.phase {
                state.uploadLastRecording()
            }
            var waited = 0
            while state.isUploading && waited < 1200 {
                try? await Task.sleep(for: .milliseconds(500))
                waited += 1
            }
            switch state.phase {
            case .uploaded(_, let result):
                FileHandle.standardError.write("auto-record: uploaded \(result.shareURL.absoluteString)\n".data(using: .utf8)!)
                print(result.shareURL.absoluteString)
            case .uploadFailed(_, let message):
                FileHandle.standardError.write("auto-record: upload failed: \(message)\n".data(using: .utf8)!)
                exit(4)
            default:
                FileHandle.standardError.write("auto-record: final phase = \(state.phase)\n".data(using: .utf8)!)
            }
            exit(0)
        }
    }
}
