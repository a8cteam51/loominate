import AppKit
import AVFoundation
import Foundation

/// Command-line entry points used for headless testing:
///   Loominate --probe <file>
///   Loominate --devices
///   Loominate --record [--seconds N] [--display INDEX | --window SUBSTRING] [--no-system-audio]
///                     [--no-mic] [--mic SUBSTRING] [--fake-camera] [--fps N] [--scale 1|2]
///                     [--quality low|medium|high] [--codec h264|hevc] [--bubble-corner NAME]
///                     [--bubble-size small|medium|large] [--out PATH]
enum CLI {
    /// Returns normally when no CLI flag is present; otherwise runs the command and exits.
    static func runIfRequested() {
        let args = Array(CommandLine.arguments.dropFirst())
        guard let command = args.first, command.hasPrefix("--") else { return }
        setvbuf(stdout, nil, _IOLBF, 0)   // line-buffer stdout so progress and URLs show up when piped
        switch command {
        case "--probe":
            guard args.count > 1 else { fail("usage: Loominate --probe <file>") }
            runBlocking { await Probe.run(path: args[1]) }
            exit(0)
        case "--devices":
            printDevices()
            exit(0)
        case "--record":
            runBlocking { await HeadlessRecording.run(Array(args.dropFirst())) }
            exit(0)
        case "--login":
            requireBundle()
            let openBrowser = !args.contains("--no-browser")
            let globalScope = args.contains("--global")
            runBlocking { await WPComCLI.login(openBrowser: openBrowser, globalScope: globalScope) }
            exit(0)
        case "--logout":
            requireBundle()
            WPComAuth.signOut()
            print("Signed out of WordPress.com.")
            exit(0)
        case "--whoami":
            requireBundle()
            WPComCLI.whoami()
            exit(0)
        case "--upload":
            requireBundle()
            guard args.count > 1 else { fail("usage: Loominate --upload <file> [--title \"…\"]") }
            var title: String?
            if let index = args.firstIndex(of: "--title"), index + 1 < args.count { title = args[index + 1] }
            runBlocking { await WPComCLI.upload(path: args[1], title: title) }
            exit(0)
        default:
            return
        }
    }

    /// Sign-in and upload need the bundle: its Info.plist carries the client secret and its
    /// code identity is what the Keychain item is bound to.
    static func requireBundle() {
        guard WPComConfig.isRunningFromBundle else {
            fail("Run this command through the app bundle: build/Loominate.app/Contents/MacOS/Loominate …")
        }
    }

    static func fail(_ message: String) -> Never {
        FileHandle.standardError.write((message + "\n").data(using: .utf8)!)
        exit(1)
    }

    /// Runs async work while servicing the main run loop, so framework callbacks that need it still fire.
    static func runBlocking(_ body: @escaping () async -> Void) {
        let semaphore = DispatchSemaphore(value: 0)
        Task.detached {
            await body()
            semaphore.signal()
        }
        while semaphore.wait(timeout: .now()) != .success {
            RunLoop.main.run(mode: .default, before: Date(timeIntervalSinceNow: 0.05))
        }
    }

    private static func printDevices() {
        print("cameras:")
        for device in DeviceCatalog.cameraDevices() {
            let mark = device.uniqueID == DeviceCatalog.cameraDevice(id: nil)?.uniqueID ? " (default)" : ""
            print("  \(device.localizedName)\(mark)  [\(device.uniqueID)]")
        }
        print("microphones:")
        for device in DeviceCatalog.microphoneDevices() {
            let mark = device.uniqueID == DeviceCatalog.microphoneDevice(id: nil)?.uniqueID ? " (default)" : ""
            print("  \(device.localizedName)\(mark)  [\(device.uniqueID)]")
        }
        print("screen recording granted: \(Permissions.screenRecordingGranted())")
        print("microphone: \(Permissions.state(for: .audio))  camera: \(Permissions.state(for: .video))")
    }
}

enum HeadlessRecording {
    static func run(_ args: [String]) async {
        var seconds = 10.0
        var displayIndex = 0
        var windowQuery: String?
        var systemAudio = true
        var microphone = true
        var micQuery: String?
        var fakeCamera = false
        var outPath: String?
        var prefs = Preferences()

        var i = 0
        func value() -> String {
            i += 1
            guard i < args.count else { CLI.fail("missing value for \(args[i - 1])") }
            return args[i]
        }
        while i < args.count {
            switch args[i] {
            case "--seconds": seconds = Double(value()) ?? seconds
            case "--display": displayIndex = Int(value()) ?? 0
            case "--window": windowQuery = value()
            case "--no-system-audio": systemAudio = false
            case "--no-mic": microphone = false
            case "--mic": micQuery = value()
            case "--fake-camera": fakeCamera = true
            case "--fps": prefs.frameRate = FrameRate(rawValue: Int(value()) ?? 30) ?? .fps30
            case "--scale": prefs.scale = CaptureScale(rawValue: Int(value()) ?? 1) ?? .one
            case "--quality": prefs.quality = QualityPreset(rawValue: value()) ?? .medium
            case "--codec": prefs.codec = VideoCodecChoice(rawValue: value()) ?? .h264
            case "--bubble-corner": prefs.bubbleCorner = BubbleCorner(rawValue: value()) ?? .bottomLeft
            case "--bubble-size": prefs.bubbleSize = BubbleSize(rawValue: value()) ?? .medium
            case "--out": outPath = value()
            default: CLI.fail("unknown option \(args[i])")
            }
            i += 1
        }

        guard Permissions.screenRecordingGranted() else {
            CLI.fail("Screen Recording permission is not granted for this process.")
        }

        do {
            let snapshot = try await ContentEnumerator.snapshot()
            let source: CaptureSource
            if let windowQuery {
                guard let window = snapshot.windows.first(where: { $0.label.localizedCaseInsensitiveContains(windowQuery) }) else {
                    CLI.fail("no window matching \"\(windowQuery)\"; available:\n  " + snapshot.windows.map(\.label).joined(separator: "\n  "))
                }
                source = .window(window.id)
                print("source: window \(window.label)")
            } else {
                guard displayIndex < snapshot.displays.count else { CLI.fail("display index out of range") }
                source = .display(snapshot.displays[displayIndex].id)
                print("source: \(snapshot.displays[displayIndex].label)")
            }

            var micID: String?
            if let micQuery {
                guard let device = DeviceCatalog.microphoneDevices().first(where: { $0.localizedName.localizedCaseInsensitiveContains(micQuery) }) else {
                    CLI.fail("no microphone matching \"\(micQuery)\"")
                }
                micID = device.uniqueID
                print("microphone: \(device.localizedName)")
            } else if microphone {
                print("microphone: system default (\(DeviceCatalog.microphoneDevice(id: nil)?.localizedName ?? "none"))")
            }

            let camera: CameraFrameSource? = fakeCamera ? FakeCameraSource() : nil
            let request = RecordingRequest(source: source, snapshot: snapshot, prefs: prefs,
                                           systemAudio: systemAudio, microphone: microphone,
                                           microphoneDeviceID: micID, cameraSource: camera,
                                           bubbleInsets: source.isWindow ? .zero : BubbleInsets.forDisplay(NSScreen.main))
            let session = RecordingSession()
            session.onStreamStopped = { error in print("stream stopped: \(error.localizedDescription)") }

            let urls: OutputLocation.URLs
            if let outPath {
                let final = URL(fileURLWithPath: outPath)
                urls = OutputLocation.URLs(temp: final.deletingPathExtension().appendingPathExtension("mov"), final: final)
                try FileManager.default.createDirectory(at: final.deletingLastPathComponent(), withIntermediateDirectories: true)
            } else {
                urls = try OutputLocation.makeURLs(folder: prefs.outputFolder)
            }

            try await session.prepare(request)
            try await Task.sleep(for: .milliseconds(700))
            try await session.beginRecording(tempURL: urls.temp)
            print("recording for \(seconds) s …")
            try await Task.sleep(for: .seconds(seconds))
            let summary = try await session.stop()
            print("saved: \(summary.url.path)")
            print("appended: \(summary.appended)  dropped: \(summary.dropped)")
            await Probe.run(path: summary.url.path)
        } catch {
            CLI.fail("record failed: \(error.localizedDescription)")
        }
    }
}

enum WPComCLI {
    static func login(openBrowser: Bool, globalScope: Bool) async {
        do {
            let account = try await WPComAuth.signIn(globalScope: globalScope, openBrowser: openBrowser) { print($0) }.account
            print("Signed in as \(account.label.isEmpty ? "(unknown user)" : account.label) · blog \(account.blogID) · scope \(account.scope)")
        } catch {
            CLI.fail("login failed: \(error.localizedDescription)")
        }
    }

    static func whoami() {
        guard let account = WPComAccount.load() else {
            print("Not signed in to WordPress.com. Run: Loominate --login")
            return
        }
        print("Signed in as \(account.label.isEmpty ? "(unknown user)" : account.label)")
        print("blog: \(account.blogURL) (\(account.blogID)) · scope: \(account.scope.isEmpty ? "this site only" : account.scope) · since \(account.signedInAt)")
        print("token in keychain: \(KeychainStore.hasToken() ? "yes" : "NO")")
        print("client secret in this build: \(WPComConfig.hasClientSecret ? "yes" : "NO")")
    }

    static func upload(path: String, title: String?) async {
        let file = URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: file.path) else { CLI.fail("no such file: \(path)") }
        let token: String?
        do {
            token = try KeychainStore.loadToken()
        } catch {
            CLI.fail("keychain: \(error.localizedDescription)")
        }
        guard let token else {
            FileHandle.standardError.write("Not signed in to WordPress.com. Run: Loominate --login\n".data(using: .utf8)!)
            exit(2)
        }
        let prefs = Preferences.load()
        let finalTitle = title ?? (prefs.titlePrefix + file.deletingPathExtension().lastPathComponent)
        let session = WPComAPI.makeSession()
        let api = WPComAPI(token: token, session: session)
        let uploader = VideoPressUploader(api: api, session: session)
        let stderr = FileHandle.standardError
        stderr.write("Uploading \(file.lastPathComponent) as \"\(finalTitle)\"\n".data(using: .utf8)!)
        do {
            let result = try await uploader.upload(file: file, title: finalTitle) { sent, total in
                let percent = total > 0 ? Int(sent * 100 / total) : 0
                stderr.write(String(format: "\r  %3d%%  %.1f / %.1f MB", percent, Double(sent) / 1e6, Double(total) / 1e6).data(using: .utf8)!)
            }
            stderr.write("\n".data(using: .utf8)!)
            print(result.shareURL.absoluteString)
        } catch WPComError.authExpired {
            stderr.write("WordPress.com rejected the saved sign-in. Run: Loominate --login\n".data(using: .utf8)!)
            exit(3)
        } catch {
            CLI.fail("upload failed: \(error.localizedDescription)")
        }
    }
}
