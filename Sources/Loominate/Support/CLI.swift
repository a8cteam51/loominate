import AppKit
import AVFoundation
import Foundation

/// Command-line entry points, mostly for headless testing. `--help` prints `usage`.
enum CLI {
    static let usage = """
    usage: Loominate [command]            (no command opens the menu bar app)

    Recording
      --devices                           list cameras and microphones
      --record [options]                  record headlessly; Ctrl-C or --seconds N stops it
          --seconds N  --display INDEX | --window SUBSTRING  --no-system-audio  --no-mic
          --mic SUBSTRING  --fake-camera  --fps N  --scale 1|2  --quality low|medium|high
          --codec h264|hevc  --bubble-corner NAME  --bubble-size small|medium|large
          --move-bubble SECONDS:CORNER (drag simulation)  --out PATH
      --probe <file>                      print a recording's tracks and sizes

    WordPress.com / VideoPress (run through the app bundle: Loominate.app/Contents/MacOS/Loominate)
      --login [--no-browser]              sign in; --no-browser prints the URL instead of opening it
      --whoami                            show the signed-in account and the chosen site
      --sites                             list your sites and which can take uploads
      --site-check <id or URL>            ask VideoPress for an upload token on one site (no upload)
      --select-site <id or URL>           choose where uploads go
      --upload <file> [--title T] [--site <id or URL>]
      --logout

    Updates (feed: GitHub Releases, or LOOMINATE_UPDATE_FEED / defaults updateFeedURL)
      --check-update                      fetch and verify the feed, compare with this build
      --install-update [--no-launch]      install the newest release over this bundle and relaunch
    """

    /// Returns normally when no CLI flag is present; otherwise runs the command and exits.
    static func runIfRequested() {
        let args = Array(CommandLine.arguments.dropFirst())
        guard let command = args.first, command.hasPrefix("-") else { return }
        setvbuf(stdout, nil, _IOLBF, 0)   // line-buffer stdout so progress and URLs show up when piped
        switch command {
        case "--help", "-h":
            print(usage)
            exit(0)
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
            runBlocking { await WPComCLI.login(openBrowser: openBrowser) }
            exit(0)
        case "--sites":
            requireBundle()
            runBlocking { await WPComCLI.sites() }
            exit(0)
        case "--site-check":
            requireBundle()
            guard args.count > 1 else { fail("usage: Loominate --site-check <id or URL>") }
            runBlocking { await WPComCLI.siteCheck(args[1]) }
            exit(0)
        case "--select-site":
            requireBundle()
            guard args.count > 1 else { fail("usage: Loominate --select-site <id or URL>") }
            runBlocking { await WPComCLI.selectSite(args[1]) }
            exit(0)
        case "--check-update":
            requireBundle()
            runBlocking { await UpdateCLI.check() }
            exit(0)
        case "--install-update":
            requireBundle()
            runBlocking { await UpdateCLI.install(launch: !args.contains("--no-launch")) }
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
            guard args.count > 1 else { fail("usage: Loominate --upload <file> [--title \"…\"] [--site <id or URL>]") }
            var title: String?
            if let index = args.firstIndex(of: "--title"), index + 1 < args.count { title = args[index + 1] }
            var site: String?
            if let index = args.firstIndex(of: "--site"), index + 1 < args.count { site = args[index + 1] }
            runBlocking { await WPComCLI.upload(path: args[1], title: title, site: site) }
            exit(0)
        default:
            // Any other dash-prefixed argument is a typo, not a request to open the app.
            FileHandle.standardError.write("Loominate: unknown option \(command)\n\n\(usage)\n".data(using: .utf8)!)
            exit(64)
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
        var moveBubble: (after: Double, corner: BubbleCorner)?
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
            case "--move-bubble":   // SECONDS:CORNER, e.g. 2:topRight — simulates dragging the self-view mid-recording
                let parts = value().split(separator: ":", maxSplits: 1).map(String.init)
                guard parts.count == 2, let after = Double(parts[0]), let corner = BubbleCorner(rawValue: parts[1]) else {
                    CLI.fail("--move-bubble wants SECONDS:CORNER, e.g. 2:topRight")
                }
                moveBubble = (after, corner)
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
            if let moveBubble, moveBubble.after < seconds {
                try await Task.sleep(for: .seconds(moveBubble.after))
                session.setBubbleCorner(moveBubble.corner)
                print("moved bubble to \(moveBubble.corner.rawValue) at \(moveBubble.after) s")
                try await Task.sleep(for: .seconds(seconds - moveBubble.after))
            } else {
                try await Task.sleep(for: .seconds(seconds))
            }
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
    static func login(openBrowser: Bool) async {
        do {
            let result = try await WPComAuth.signIn(openBrowser: openBrowser) { print($0) }
            var account = result.account
            print("Signed in as \(account.label.isEmpty ? "(unknown user)" : account.label) · scope \(account.scope)")
            let api = WPComAPI(token: result.accessToken, session: WPComAPI.makeSession())
            let sites = try await api.sites()
            let eligible = sites.filter(\.isEligible)
            if eligible.count == 1 {
                account.select(eligible[0])
                account.save()
                print("Uploads will go to \(eligible[0].label).")
            } else {
                print("\(eligible.count) of your \(sites.count) sites can take uploads. Pick one with: Loominate --select-site <id or URL>")
            }
        } catch {
            CLI.fail("login failed: \(error.localizedDescription)")
        }
    }

    private static func api() throws -> WPComAPI {
        guard let token = try KeychainStore.loadToken() else { throw WPComError.notSignedIn }
        return WPComAPI(token: token, session: WPComAPI.makeSession())
    }

    static func sites() async {
        do {
            guard let account = WPComAccount.load() else { throw WPComError.notSignedIn }
            guard account.hasGlobalScope else { CLI.fail("This sign-in is limited to one site. Run: Loominate --login") }
            let sites = try await api().sites()
            for site in sites {
                let mark = site.id == account.siteID ? "*" : " "
                let status = site.isEligible ? "VideoPress" : (!site.canUpload ? "no upload rights" : "no VideoPress")
                print("\(mark) \(String(site.id).padding(toLength: 10, withPad: " ", startingAt: 0)) \(site.label.padding(toLength: 48, withPad: " ", startingAt: 0)) \(status)\(site.isJetpack ? " (Jetpack)" : "")")
            }
            print("\(sites.filter(\.isEligible).count) of \(sites.count) sites have VideoPress and can take uploads; * marks the selected one.")
        } catch {
            CLI.fail("sites failed: \(error.localizedDescription)")
        }
    }

    /// Settles "can I really upload there?" by asking VideoPress for an upload token, which is the
    /// first step of a real upload, without sending any video.
    static func siteCheck(_ query: String) async {
        do {
            let api = try api()
            let sites = try await api.sites()
            guard let site = resolveSite(query, in: sites) else { CLI.fail("no site matching \"\(query)\"; run --sites to list them") }
            print("\(site.label) · id \(site.id) · \(site.isJetpack ? (site.isAtomic ? "WordPress.com (Atomic)" : "Jetpack") : "WordPress.com")")
            print("upload rights: \(site.canUpload ? "yes" : "no") · VideoPress flag: \(site.hasVideoPress ? "yes" : "no") · Loominate lists it as \(site.isEligible ? "eligible" : "not eligible")")
            do {
                _ = try await api.videoPressUploadToken(blogID: site.id)
                print("VideoPress issued an upload token for this site, so uploads would work.")
            } catch {
                print("VideoPress refused an upload token: \(error.localizedDescription)")
            }
        } catch {
            CLI.fail("site-check failed: \(error.localizedDescription)")
        }
    }

    static func resolveSite(_ query: String, in sites: [WPComSite]) -> WPComSite? {
        if let id = Int(query), let site = sites.first(where: { $0.id == id }) { return site }
        let needle = query.lowercased()
        return sites.first { $0.url.lowercased().contains(needle) || $0.name.lowercased() == needle }
    }

    static func selectSite(_ query: String) async {
        do {
            guard var account = WPComAccount.load() else { throw WPComError.notSignedIn }
            let sites = try await api().sites()
            guard let site = resolveSite(query, in: sites) else { CLI.fail("no site matching \"\(query)\"; run --sites to list them") }
            guard site.isEligible else { CLI.fail("\(site.label) cannot take uploads (\(site.canUpload ? "no VideoPress" : "no upload rights"))") }
            account.select(site)
            account.save()
            print("Uploads will go to \(site.label).")
        } catch {
            CLI.fail("select-site failed: \(error.localizedDescription)")
        }
    }

    static func whoami() {
        guard let account = WPComAccount.load() else {
            print("Not signed in to WordPress.com. Run: Loominate --login")
            return
        }
        print("Signed in as \(account.label.isEmpty ? "(unknown user)" : account.label) · scope: \(account.hasGlobalScope ? "all sites" : "one site only (sign in again)") · since \(account.signedInAt)")
        print("uploads go to: \(account.siteLabel ?? "no site chosen (run --sites, then --select-site)")")
        print("token in keychain: \(KeychainStore.hasToken() ? "yes" : "NO")")
        print("client secret in this build: \(WPComConfig.hasClientSecret ? "yes" : "NO")")
    }

    static func upload(path: String, title: String?, site: String?) async {
        let file = URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: file.path) else { CLI.fail("no such file: \(path)") }
        let token: String?
        do {
            token = try KeychainStore.loadToken()
        } catch {
            CLI.fail("keychain: \(error.localizedDescription)")
        }
        guard let token, let account = WPComAccount.load() else {
            FileHandle.standardError.write("Not signed in to WordPress.com. Run: Loominate --login\n".data(using: .utf8)!)
            exit(2)
        }
        let session = WPComAPI.makeSession()
        let api = WPComAPI(token: token, session: session)
        var blogID = account.siteID
        var siteLabel = account.siteLabel ?? ""
        if let site {
            do {
                guard let match = resolveSite(site, in: try await api.sites()), match.isEligible else {
                    CLI.fail("no uploadable site matching \"\(site)\"; run --sites to list them")
                }
                blogID = match.id
                siteLabel = match.label
            } catch {
                CLI.fail("sites failed: \(error.localizedDescription)")
            }
        }
        guard let blogID else {
            FileHandle.standardError.write("No site chosen. Run: Loominate --sites, then --select-site <id or URL>, or pass --site\n".data(using: .utf8)!)
            exit(2)
        }
        let prefs = Preferences.load()
        let finalTitle = title ?? (prefs.titlePrefix + file.deletingPathExtension().lastPathComponent)
        let uploader = VideoPressUploader(api: api, session: session)
        let stderr = FileHandle.standardError
        stderr.write("Uploading \(file.lastPathComponent) to \(siteLabel) as \"\(finalTitle)\"\n".data(using: .utf8)!)
        do {
            let result = try await uploader.upload(file: file, title: finalTitle, blogID: blogID) { sent, total in
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


// MARK: - Updates

enum UpdateCLI {
    static var running: (version: String, build: Int) {
        let info = Bundle.main.infoDictionary ?? [:]
        return (info["CFBundleShortVersionString"] as? String ?? "0.0.0", Int(info["CFBundleVersion"] as? String ?? "") ?? 0)
    }

    static func check() async {
        print("feed: \(UpdateConfig.feedURL.absoluteString)\(UpdateConfig.usesFeedOverride ? " (override)" : "")")
        do {
            let payload = try await UpdateFeed().fetchManifest()
            let me = running
            print("latest: \(payload.version) (\(payload.build)), published \(payload.publishedAt), macOS \(payload.minimumSystemVersion)+")
            print("zip: \(UpdateConfig.zipURL(for: payload).absoluteString) · \(payload.zip.size) bytes · sha256 \(payload.zip.sha256)")
            print("running: \(me.version) (\(me.build)) at \(Bundle.main.bundleURL.path)")
            if payload.isNewer(thanVersion: me.version, build: me.build) {
                print("update available")
                do {
                    _ = try UpdateInstaller.preflight()
                    print("this copy can update itself")
                } catch {
                    print("but this copy cannot update itself: \(error.localizedDescription)")
                }
            } else {
                print("up to date")
            }
        } catch {
            CLI.fail("check failed: \(error.localizedDescription)")
        }
    }

    static func install(launch: Bool) async {
        let stderr = FileHandle.standardError
        do {
            let payload = try await UpdateFeed().fetchManifest()
            let me = running
            guard payload.isNewer(thanVersion: me.version, build: me.build) else {
                print("already up to date: \(me.version) (\(me.build)); the feed offers \(payload.version) (\(payload.build))")
                return
            }
            stderr.write("Installing \(payload.version) (\(payload.build)) over \(Bundle.main.bundleURL.path)\n".data(using: .utf8)!)
            let old = try await UpdateInstaller.install(payload, session: UpdateFeed.makeSession(), launchAfter: launch) { step in
                switch step {
                case .downloading(let done, let total):
                    stderr.write("  downloaded \(done)/\(total)\n".data(using: .utf8)!)
                case .verifying:
                    stderr.write("  verifying\n".data(using: .utf8)!)
                case .installing:
                    stderr.write("  installing\n".data(using: .utf8)!)
                case .identityChange(let notice):
                    stderr.write("  note: \(notice)\n".data(using: .utf8)!)
                }
            }
            print("Installed \(payload.version) (\(payload.build)). The old bundle at \(old.path) is removed\(launch ? " and the app relaunched" : "") as soon as this process exits.")
        } catch {
            CLI.fail("install failed: \(error.localizedDescription)")
        }
    }
}
