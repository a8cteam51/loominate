import AppKit
import AVFoundation
import Foundation
import Observation

@MainActor @Observable
final class AppState {
    enum SourceKind: String, CaseIterable, Identifiable {
        case display, window
        var id: String { rawValue }
        var label: String { self == .display ? "Screen" : "Window" }
    }

    enum Phase: Equatable {
        case idle
        case preparing
        case countdown(Int)
        case recording
        case saving
        case saved(URL)
        case failed(String)
        case uploading(URL)
        case uploaded(URL, UploadResult)
        case uploadFailed(URL, String)
    }

    var prefs: Preferences
    let devices = DeviceCatalog()
    let updates = UpdateController()

    var sourceKind: SourceKind = .display
    var selectedDisplayID: CGDirectDisplayID?
    var selectedWindowID: CGWindowID?
    private(set) var displays: [DisplayInfo] = []
    private(set) var windows: [WindowInfo] = []

    private(set) var screenPermission = false
    private(set) var microphonePermission: PermissionState = .notDetermined
    private(set) var cameraPermission: PermissionState = .notDetermined

    private(set) var phase: Phase = .idle
    private(set) var elapsed: TimeInterval = 0
    private(set) var lastRecording: URL?
    var warning: String?

    // WordPress.com / VideoPress
    private(set) var account: WPComAccount?
    private(set) var isSigningIn = false
    var signInError: String?
    private(set) var sites: [WPComSite] = []
    private(set) var isLoadingSites = false
    var sitesError: String?
    /// Text typed into the site picker's filter box; people at Automattic belong to hundreds of P2s.
    var siteFilter = ""
    @ObservationIgnored private var sitesLoadedThisLaunch = false
    var uploadTitle = ""
    private(set) var uploadProgress: Double = 0
    private(set) var uploadBytes: (sent: Int64, total: Int64) = (0, 0)
    private(set) var lastShareURL: URL?
    @ObservationIgnored private var uploadTask: Task<Void, Never>?
    @ObservationIgnored private var signInTask: Task<Void, Never>?
    @ObservationIgnored private var lastUploadMediaID: Int?
    @ObservationIgnored private let uploadSession = WPComAPI.makeSession()
    /// Read from the Keychain at most once per launch, so macOS asks at most once.
    @ObservationIgnored private var cachedToken: String?

    @ObservationIgnored private var snapshot: ShareableSnapshot?
    @ObservationIgnored private var session: RecordingSession?
    @ObservationIgnored private var camera: CameraCapture?
    @ObservationIgnored private var previewPanel: CameraPreviewPanel?
    @ObservationIgnored private var hud: RecordingHUD?
    @ObservationIgnored private var resultHUD: ResultHUD?
    @ObservationIgnored private var countdownOverlay: CountdownOverlay?
    @ObservationIgnored private var elapsedTimer: Timer?
    @ObservationIgnored private var countdownTask: Task<Void, Never>?
    @ObservationIgnored private var recordingStart: Date?

    init() {
        var loaded = Preferences.load()
        loaded.cameraEnabled = false   // the preview window only appears once the user asks for it
        prefs = loaded
        account = WPComAccount.load()
        refreshPermissions()
        updates.isAppBusy = { [weak self] in self?.isBusy ?? false }
        updates.automaticChecksEnabled = { [weak self] in self?.prefs.checkForUpdatesAutomatically ?? true }
        Notifier.openUpdatesHandler = { [weak self] in Task { @MainActor in self?.openSettings() } }
    }

    // MARK: Derived state

    var isRecording: Bool { phase == .recording }

    var isBusy: Bool {
        switch phase {
        case .idle, .saved, .failed, .uploaded, .uploadFailed: return false
        default: return true
        }
    }

    var isUploading: Bool {
        if case .uploading = phase { return true }
        return false
    }

    var hasClientSecret: Bool { WPComConfig.hasClientSecret }
    /// A token scoped to one site (from an earlier build) cannot list sites; ask once for a fresh sign-in.
    var needsReSignIn: Bool { account.map { !$0.hasGlobalScope } ?? false }
    var hasSite: Bool { account?.siteID != nil }
    var canUpload: Bool { account != nil && !needsReSignIn && hasSite && hasClientSecret }
    var eligibleSites: [WPComSite] { sites.filter(\.isEligible) }
    var filteredEligibleSites: [WPComSite] {
        let needle = siteFilter.trimmingCharacters(in: .whitespaces)
        guard !needle.isEmpty else { return eligibleSites }
        return eligibleSites.filter { $0.label.localizedCaseInsensitiveContains(needle) || String($0.id) == needle }
    }
    var selectedSite: WPComSite? { sites.first { $0.id == account?.siteID } }
    var uploadPercentText: String { "\(Int((uploadProgress * 100).rounded()))%" }

    var selectedSource: CaptureSource? {
        switch sourceKind {
        case .display: return selectedDisplayID.map { .display($0) }
        case .window: return selectedWindowID.map { .window($0) }
        }
    }

    var canRecord: Bool { screenPermission && !isBusy && selectedSource != nil }

    var elapsedText: String {
        let total = Int(elapsed)
        return String(format: "%02d:%02d", total / 60, total % 60)
    }

    // MARK: Permissions and content

    func refreshPermissions() {
        screenPermission = Permissions.screenRecordingGranted()
        microphonePermission = Permissions.state(for: .audio)
        cameraPermission = Permissions.state(for: .video)
    }

    func requestScreenPermission() {
        Permissions.requestScreenRecording()
        refreshPermissions()
    }

    func panelDidAppear() async {
        refreshPermissions()
        devices.refresh()
        if let notice = updates.postInstallNotice {
            warning = notice
            updates.postInstallNotice = nil
        }
        await refreshContent()
        await loadSitesIfNeeded()
    }

    func refreshContent() async {
        guard screenPermission else { return }
        do {
            let snapshot = try await ContentEnumerator.snapshot()
            self.snapshot = snapshot
            displays = snapshot.displays
            windows = snapshot.windows
            if selectedDisplayID == nil || !displays.contains(where: { $0.id == selectedDisplayID }) {
                selectedDisplayID = displays.first(where: \.isMain)?.id ?? displays.first?.id
            }
            if selectedWindowID == nil || !windows.contains(where: { $0.id == selectedWindowID }) {
                selectedWindowID = windows.first?.id
            }
        } catch {
            warning = error.localizedDescription
            Log.app.error("content refresh failed: \(error.localizedDescription)")
        }
    }

    // MARK: Toggles

    func setCameraEnabled(_ on: Bool) async {
        if on {
            if cameraPermission == .notDetermined {
                _ = await Permissions.request(.video)
                refreshPermissions()
            }
            guard cameraPermission == .granted else {
                prefs.cameraEnabled = false
                prefs.save()
                warning = "Camera access is off. Allow it in System Settings → Privacy & Security → Camera."
                return
            }
            do {
                try startCameraPreview()
                prefs.cameraEnabled = true
                warning = nil
            } catch {
                prefs.cameraEnabled = false
                warning = error.localizedDescription
            }
        } else {
            stopCameraPreview()
            prefs.cameraEnabled = false
        }
        prefs.save()
    }

    func selectCamera(_ id: String?) async {
        prefs.cameraDeviceID = id
        prefs.save()
        guard prefs.cameraEnabled else { return }
        do {
            try startCameraPreview()
        } catch {
            warning = error.localizedDescription
        }
    }

    func setMicrophoneEnabled(_ on: Bool) async {
        if on {
            if microphonePermission == .notDetermined {
                _ = await Permissions.request(.audio)
                refreshPermissions()
            }
            guard microphonePermission == .granted else {
                prefs.microphoneEnabled = false
                prefs.save()
                warning = "Microphone access is off. Allow it in System Settings → Privacy & Security → Microphone."
                return
            }
            warning = nil
        }
        prefs.microphoneEnabled = on
        prefs.save()
    }

    func selectMicrophone(_ id: String?) {
        prefs.microphoneDeviceID = id
        prefs.save()
    }

    func setSystemAudioEnabled(_ on: Bool) {
        prefs.systemAudioEnabled = on
        prefs.save()
    }

    private func startCameraPreview() throws {
        guard let device = DeviceCatalog.cameraDevice(id: prefs.cameraDeviceID) else {
            throw RecordingError.cameraUnavailable("No camera")
        }
        let capture = camera ?? CameraCapture()
        try capture.configure(device: device)
        capture.start()
        camera = capture
        if previewPanel == nil {
            let panel = CameraPreviewPanel(previewLayer: capture.makePreviewLayer(),
                                           size: prefs.bubbleSize, corner: prefs.bubbleCorner)
            panel.onSnap = { [weak self] corner in
                guard let self, self.prefs.bubbleCorner != corner else { return }
                self.prefs.bubbleCorner = corner
                self.prefs.save()
            }
            previewPanel = panel
        } else {
            previewPanel?.apply(size: prefs.bubbleSize, corner: prefs.bubbleCorner, animated: false)
        }
        previewPanel?.orderFrontRegardless()
    }

    /// Settings changed the bubble size or corner: move the self-view to match.
    func applyBubbleLayout() {
        previewPanel?.apply(size: prefs.bubbleSize, corner: prefs.bubbleCorner, animated: true)
    }

    private func stopCameraPreview() {
        previewPanel?.orderOut(nil)
        previewPanel = nil
        camera?.stop()
        camera = nil
    }

    // MARK: Recording

    func startRecording() async {
        guard canRecord, let source = selectedSource else { return }
        warning = nil
        uploadTitle = ""
        hideResultHUD()

        // The mic toggle defaults to on, so ask for permission here if nobody has yet.
        if prefs.microphoneEnabled && microphonePermission == .notDetermined {
            _ = await Permissions.request(.audio)
            refreshPermissions()
        }
        if prefs.microphoneEnabled && microphonePermission != .granted {
            warning = "Recording without the microphone: allow it in System Settings → Privacy & Security → Microphone."
        }
        Log.note("start requested: source=\(source) mic=\(prefs.microphoneEnabled) micPermission=\(microphonePermission) micDevice=\(prefs.microphoneDeviceID ?? "default") systemAudio=\(prefs.systemAudioEnabled) camera=\(prefs.cameraEnabled) cameraPermission=\(cameraPermission)")
        phase = .preparing

        // The preview is hidden after each recording; bring it back for this one.
        if prefs.cameraEnabled && cameraPermission == .granted && camera == nil {
            do { try startCameraPreview() } catch { warning = error.localizedDescription }
        }

        if let free = OutputLocation.freeSpace(at: FileManager.default.homeDirectoryForCurrentUser),
           free < OutputLocation.minimumFreeBytes {
            phase = .failed(RecordingError.insufficientDiskSpace.localizedDescription)
            return
        }

        // ScreenCaptureKit only lists (and can only exclude) apps that have a window on screen when
        // the content snapshot is taken. Put the countdown window up first, empty, so this app is
        // listed and every window of ours (countdown, HUD, self-view) stays out of the recording.
        let targetScreen = screenForSource(source)
        let overlay = CountdownOverlay(screen: targetScreen)
        overlay.orderFrontRegardless()
        countdownOverlay = overlay
        try? await Task.sleep(for: .milliseconds(150))

        await refreshContent()
        guard let snapshot, snapshot.ownApplication != nil else {
            overlay.orderOut(nil)
            countdownOverlay = nil
            phase = .failed(snapshot == nil ? ContentError.sourceUnavailable.localizedDescription
                                           : "Could not exclude Loominate's own windows from the capture. Try again.")
            return
        }

        let micID = devices.isAttachedMicrophone(prefs.microphoneDeviceID) ? prefs.microphoneDeviceID : nil
        let request = RecordingRequest(source: source,
                                       snapshot: snapshot,
                                       prefs: prefs,
                                       systemAudio: prefs.systemAudioEnabled,
                                       microphone: prefs.microphoneEnabled && microphonePermission == .granted,
                                       microphoneDeviceID: micID,
                                       cameraSource: prefs.cameraEnabled ? camera : nil,
                                       bubbleInsets: source.isWindow ? .zero : BubbleInsets.forDisplay(targetScreen))
        let session = RecordingSession()
        session.onStreamStopped = { [weak self] error in
            Task { @MainActor in
                guard let self else { return }
                self.warning = RecordingError.streamStopped(error).localizedDescription
                if self.phase == .recording {
                    await self.stopRecording()
                } else {
                    self.cancelCountdown()
                }
            }
        }
        self.session = session

        do {
            try await session.prepare(request)
        } catch {
            overlay.orderOut(nil)
            countdownOverlay = nil
            self.session = nil
            phase = .failed(error.localizedDescription)
            return
        }

        closeMenuPanel()

        // Countdown (the stream warms up underneath it).
        let seconds = max(prefs.countdownSeconds, 0)
        let task = Task { [weak self] in
            guard let self else { return }
            if seconds > 0 {
                for remaining in stride(from: seconds, to: 0, by: -1) {
                    if Task.isCancelled { break }
                    self.phase = .countdown(remaining)
                    overlay.show(remaining)
                    try? await Task.sleep(for: .seconds(1))
                }
            } else {
                try? await Task.sleep(for: .milliseconds(600))
            }
            overlay.orderOut(nil)
            self.countdownOverlay = nil
            // Let the capture deliver a frame without the countdown before the writer starts.
            try? await Task.sleep(for: .milliseconds(120))
        }
        countdownTask = task
        await task.value
        countdownTask = nil
        if task.isCancelled {
            overlay.orderOut(nil)
            countdownOverlay = nil
            await session.cancel()
            self.session = nil
            phase = .idle
            return
        }

        do {
            let urls = try OutputLocation.makeURLs(folder: prefs.outputFolder)
            try await session.beginRecording(tempURL: urls.temp)
        } catch {
            await session.cancel()
            self.session = nil
            phase = .failed(error.localizedDescription)
            return
        }

        recordingStart = Date()
        elapsed = 0
        phase = .recording
        elapsedTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let start = self.recordingStart else { return }
                self.elapsed = Date().timeIntervalSince(start)
            }
        }
        if hud == nil { hud = RecordingHUD(state: self) }
        hud?.orderFrontRegardless()
    }

    func cancelCountdown() {
        countdownTask?.cancel()
    }

    func stopRecording() async {
        guard phase == .recording, let session else { return }
        elapsedTimer?.invalidate()
        elapsedTimer = nil
        hud?.orderOut(nil)
        stopCameraPreview()   // the self-view has no job once the recording ends; the camera setting stays on
        phase = .saving
        do {
            let summary = try await session.stop()
            lastRecording = summary.url
            phase = .saved(summary.url)
            Log.note("saved \(summary.url.lastPathComponent) duration=\(String(format: "%.1f", summary.duration))s")
            showResultHUD()
            if prefs.autoUpload && canUpload {
                startUpload(file: summary.url)
            } else if prefs.revealInFinderAfterSave {
                NSWorkspace.shared.activateFileViewerSelecting([summary.url])
            }
        } catch {
            phase = .failed(error.localizedDescription)
            Log.note("stop failed: \(error.localizedDescription)")
        }
        self.session = nil
    }

    /// Floating "what now?" panel shown after a recording stops.
    private func showResultHUD() {
        if resultHUD == nil { resultHUD = ResultHUD(state: self) }
        resultHUD?.orderFrontRegardless()
    }

    private func hideResultHUD() {
        resultHUD?.orderOut(nil)
    }

    /// Moves the just-recorded file to the Trash (outtakes) and clears the result.
    func discardLastRecording() {
        var file: URL?
        switch phase {
        case .saved(let url), .uploadFailed(let url, _): file = url
        default: file = lastRecording
        }
        if let file {
            do {
                try FileManager.default.trashItem(at: file, resultingItemURL: nil)
                Log.note("discarded \(file.lastPathComponent) to the Trash")
            } catch {
                warning = "Could not move the recording to the Trash: \(error.localizedDescription)"
            }
            if lastRecording == file { lastRecording = nil }
        }
        dismissResult()
    }

    func dismissResult() {
        phase = .idle
        uploadTitle = ""
        hideResultHUD()
    }

    // MARK: WordPress.com sign-in

    func signIn() {
        guard !isSigningIn else { return }
        isSigningIn = true
        signInError = nil
        signInTask = Task { [weak self] in
            do {
                let result = try await WPComAuth.signIn()
                self?.account = result.account
                self?.cachedToken = result.accessToken
                await self?.loadSites()
            } catch WPComError.cancelled {
                // user cancelled
            } catch {
                self?.signInError = error.localizedDescription
            }
            self?.isSigningIn = false
            self?.signInTask = nil
        }
    }

    func cancelSignIn() {
        signInTask?.cancel()
    }

    func signOut() {
        WPComAuth.signOut()
        account = nil
        cachedToken = nil
        sites = []
        sitesError = nil
    }

    // MARK: Sites

    /// Loads the site list once per launch when signed in; Settings and the panel call this.
    func loadSitesIfNeeded() async {
        guard account != nil, !needsReSignIn, !sitesLoadedThisLaunch, !isLoadingSites else { return }
        await loadSites()
    }

    func loadSites() async {
        guard account != nil, !needsReSignIn, !isLoadingSites else { return }
        isLoadingSites = true
        defer { isLoadingSites = false }
        do {
            let api = WPComAPI(token: try accessToken(), session: uploadSession)
            let fetched = try await api.sites()
            sites = fetched.sorted { $0.label.localizedCaseInsensitiveCompare($1.label) == .orderedAscending }
            sitesError = nil
            sitesLoadedThisLaunch = true
            let eligible = eligibleSites
            if let current = account?.siteID, !eligible.contains(where: { $0.id == current }) {
                selectSite(nil)   // the chosen site is gone or lost VideoPress
            }
            if account?.siteID == nil, eligible.count == 1 {
                selectSite(eligible[0])
            }
            Log.note("sites loaded: \(sites.count) total, \(eligible.count) with VideoPress; selected=\(account?.siteID.map(String.init) ?? "none")")
        } catch WPComError.authExpired {
            signOut()
            signInError = WPComError.authExpired.localizedDescription
        } catch {
            sitesError = error.localizedDescription
            Log.note("sites load failed: \(error.localizedDescription)")
        }
    }

    func selectSite(_ site: WPComSite?) {
        guard var account else { return }
        account.select(site)
        account.save()
        self.account = account
    }

    /// Opens the Settings window and brings the app forward (used from panels outside the SwiftUI scene).
    func openSettings() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
    }

    /// The access token, read from the Keychain on first use and then kept in memory.
    private func accessToken() throws -> String {
        if let cachedToken { return cachedToken }
        guard let token = try KeychainStore.loadToken() else { throw WPComError.notSignedIn }
        cachedToken = token
        return token
    }

    // MARK: Upload

    /// Title that will be applied on VideoPress: prefix + what the user typed, or the file's own name.
    func effectiveTitle(for file: URL) -> String {
        let base = uploadTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = base.isEmpty ? file.deletingPathExtension().lastPathComponent : base
        return prefs.titlePrefix + name
    }

    func uploadLastRecording() {
        if case .saved(let url) = phase { startUpload(file: url) }
        else if case .uploadFailed(let url, _) = phase { startUpload(file: url) }
    }

    func startUpload(file: URL) {
        guard !isUploading else { return }
        guard canUpload, let blogID = account?.siteID else {
            let reason = (account == nil || needsReSignIn)
                ? WPComError.notSignedIn.localizedDescription
                : "Choose a site to upload to in Settings."
            phase = .uploadFailed(file, reason)
            return
        }
        let size = (try? FileManager.default.attributesOfItem(atPath: file.path)[.size] as? NSNumber)?.int64Value ?? 0
        uploadProgress = 0
        uploadBytes = (0, size)
        phase = .uploading(file)
        let initialTitle = effectiveTitle(for: file)
        Log.note("upload starting: \(file.lastPathComponent) (\(size) bytes) title=\"\(initialTitle)\"")
        uploadTask = Task { [weak self] in
            guard let self else { return }
            do {
                let token = try self.accessToken()
                let api = WPComAPI(token: token, session: self.uploadSession)
                let uploader = VideoPressUploader(api: api, session: self.uploadSession)
                var result = try await uploader.upload(file: file, title: initialTitle, blogID: blogID) { sent, total in
                    Task { @MainActor in
                        self.uploadBytes = (sent, total)
                        self.uploadProgress = total > 0 ? Double(sent) / Double(total) : 0
                    }
                }
                // The title may have been edited while the upload ran.
                let finalTitle = self.effectiveTitle(for: file)
                if finalTitle != initialTitle {
                    try? await api.setMediaTitle(blogID: blogID, mediaID: result.mediaID, title: finalTitle)
                    result.title = finalTitle
                }
                self.finishUpload(file: file, result: result)
            } catch is CancellationError {
                self.phase = .uploadFailed(file, "Upload cancelled. The recording is still saved locally.")
            } catch WPComError.cancelled {
                self.phase = .uploadFailed(file, "Upload cancelled. The recording is still saved locally.")
            } catch WPComError.authExpired {
                self.signOut()
                self.phase = .uploadFailed(file, WPComError.authExpired.localizedDescription)
                Log.note("upload failed: sign-in rejected")
            } catch {
                self.phase = .uploadFailed(file, error.localizedDescription)
                Log.note("upload failed: \(error.localizedDescription)")
            }
            self.uploadTask = nil
        }
    }

    private func finishUpload(file: URL, result: UploadResult) {
        uploadProgress = 1
        lastShareURL = result.shareURL
        lastUploadMediaID = result.mediaID
        if prefs.copyLinkAfterUpload {
            copy(result.shareURL.absoluteString)
        }
        phase = .uploaded(file, result)
        Log.note("upload finished: \(result.shareURL.absoluteString)")
        if prefs.notifyWhenUploaded {
            Notifier.shared.notify(title: prefs.copyLinkAfterUpload ? "Link copied" : "Upload finished",
                                   body: result.title, url: result.shareURL)
        }
        if prefs.deleteLocalAfterUpload {
            try? FileManager.default.removeItem(at: file)
            if lastRecording == file { lastRecording = nil }
        }
    }

    func cancelUpload() {
        uploadTask?.cancel()
    }

    /// Re-applies an edited title to the uploaded video.
    func saveUploadedTitle() async {
        guard case .uploaded(let file, var result) = phase, let mediaID = lastUploadMediaID,
              let blogID = account?.siteID else { return }
        let title = effectiveTitle(for: file)
        guard title != result.title else { return }
        do {
            let api = WPComAPI(token: try accessToken(), session: uploadSession)
            try await api.setMediaTitle(blogID: blogID, mediaID: mediaID, title: title)
            result.title = title
            phase = .uploaded(file, result)
        } catch {
            warning = "Could not update the title: \(error.localizedDescription)"
        }
    }

    func copyShareLink() {
        guard let lastShareURL else { return }
        copy(lastShareURL.absoluteString)
    }

    func openShareLink() {
        guard let lastShareURL else { return }
        NSWorkspace.shared.open(lastShareURL)
    }

    private func copy(_ string: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
    }

    func revealLastRecording() {
        guard let lastRecording else { return }
        NSWorkspace.shared.activateFileViewerSelecting([lastRecording])
    }

    func copyLastRecordingPath() {
        guard let lastRecording else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(lastRecording.path, forType: .string)
    }

    func chooseOutputFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.directoryURL = prefs.outputFolder
        NSApp.activate(ignoringOtherApps: true)
        if panel.runModal() == .OK, let url = panel.url {
            prefs.outputFolderPath = url.path
            prefs.save()
        }
    }

    // MARK: Helpers

    private func screenForSource(_ source: CaptureSource) -> NSScreen? {
        guard case .display(let id) = source else { return NSScreen.main }
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        return NSScreen.screens.first { ($0.deviceDescription[key] as? NSNumber)?.uint32Value == id } ?? NSScreen.main
    }

    /// Hides the menu bar panel so it does not cover what the user is about to record.
    private func closeMenuPanel() {
        for window in NSApp.windows where window.isVisible {
            if window is CameraPreviewPanel || window is RecordingHUD || window is CountdownOverlay { continue }
            if window.className.contains("StatusBar") { continue }   // the menu bar item itself
            if !window.title.isEmpty { continue }                     // the Settings window
            window.orderOut(nil)
        }
    }
}
