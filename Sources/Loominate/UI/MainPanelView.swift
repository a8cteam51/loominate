import SwiftUI

struct MainPanelView: View {
    @Bindable var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            if state.updates.shouldOffer && !state.isBusy {
                updateRow
            }
            if state.screenPermission {
                sourceSection
                Divider()
                inputsSection
                Divider()
                actionSection
            } else {
                screenPermissionSection
            }
            if let warning = state.warning {
                Text(warning)
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .frame(width: 340)
        .onAppear { Task { await state.panelDidAppear() } }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Text("Loominate").font(.headline)
            Spacer()
            SettingsLink {
                Image(systemName: "gearshape")
            }
            .buttonStyle(.plain)
            .simultaneousGesture(TapGesture().onEnded { NSApp.activate(ignoringOtherApps: true) })
            .help("Settings")
            Button {
                NSApp.terminate(nil)
            } label: {
                Image(systemName: "power")
            }
            .buttonStyle(.plain)
            .keyboardShortcut("q", modifiers: .command)
            .help("Quit Loominate (⌘Q)")
            .disabled(state.isRecording || state.isUploading)
        }
    }

    private var updateRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "arrow.down.circle.fill").foregroundStyle(.tint)
            switch state.updates.phase {
            case .downloading(let fraction):
                Text("Downloading \(Int((fraction * 100).rounded()))%…")
                Spacer()
            case .verifying, .installing:
                Text("Installing…")
                Spacer()
            case .blocked:
                Text("Can't update from this location.")
                Spacer()
                Button("Details") { state.openSettings() }.buttonStyle(.link)
            case .failed:
                Text("The update didn't install.")
                Spacer()
                Button("Details") { state.openSettings() }.buttonStyle(.link)
            default:
                Text("Loominate \(state.updates.availableUpdate?.version ?? "") is available")
                Spacer()
                Button("Update") { state.updates.install() }.buttonStyle(.link)
            }
        }
        .font(.caption)
        .padding(8)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
    }

    private var screenPermissionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Screen Recording permission needed", systemImage: "exclamationmark.triangle")
                .font(.subheadline.weight(.semibold))
            Text("Loominate needs permission to see your screen. After you allow it, quit and reopen Loominate.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("Request Permission") { state.requestScreenPermission() }
                Button("Open System Settings") { Permissions.openSystemSettings(.screenRecording) }
                Button("Quit") { NSApp.terminate(nil) }
            }
            .controlSize(.small)
        }
    }

    private var sourceSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Source", selection: $state.sourceKind) {
                ForEach(AppState.SourceKind.allCases) { kind in
                    Text(kind.label).tag(kind)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .disabled(state.isBusy)

            switch state.sourceKind {
            case .display:
                if state.displays.count > 1 {
                    Picker("Display", selection: $state.selectedDisplayID) {
                        ForEach(state.displays) { display in
                            Text(display.label).tag(Optional(display.id))
                        }
                    }
                    .disabled(state.isBusy)
                } else if let display = state.displays.first {
                    Text(display.label).font(.caption).foregroundStyle(.secondary)
                }
            case .window:
                HStack {
                    Picker("Window", selection: $state.selectedWindowID) {
                        if state.windows.isEmpty {
                            Text("No windows").tag(CGWindowID?.none)
                        }
                        ForEach(state.windows) { window in
                            Text(window.label).lineLimit(1).tag(Optional(window.id))
                        }
                    }
                    .labelsHidden()
                    .disabled(state.isBusy)
                    Button {
                        Task { await state.refreshContent() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.borderless)
                    .help("Refresh window list")
                }
            }
        }
    }

    private var inputsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Toggle("Camera", isOn: Binding(
                    get: { state.prefs.cameraEnabled },
                    set: { on in Task { await state.setCameraEnabled(on) } }))
                    .toggleStyle(.switch)
                    .controlSize(.small)
                Spacer()
                Picker("", selection: Binding(
                    get: { state.prefs.cameraDeviceID },
                    set: { id in Task { await state.selectCamera(id) } })) {
                    Text(defaultLabel(for: state.devices.defaultCameraID, in: state.devices.cameras)).tag(String?.none)
                    ForEach(state.devices.cameras) { camera in
                        Text(camera.name).tag(Optional(camera.id))
                    }
                }
                .labelsHidden()
                .frame(maxWidth: 190)
                .disabled(!state.prefs.cameraEnabled || state.isBusy)
            }
            .disabled(state.isBusy)
            permissionHint(state.cameraPermission, pane: .camera, name: "Camera")
            if state.prefs.cameraEnabled && !state.isBusy {
                Text("The self-view appears while you record and goes away when you stop.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            HStack {
                Toggle("Microphone", isOn: Binding(
                    get: { state.prefs.microphoneEnabled },
                    set: { on in Task { await state.setMicrophoneEnabled(on) } }))
                    .toggleStyle(.switch)
                    .controlSize(.small)
                Spacer()
                Picker("", selection: Binding(
                    get: { state.prefs.microphoneDeviceID },
                    set: { id in state.selectMicrophone(id) })) {
                    Text(defaultLabel(for: state.devices.defaultMicrophoneID, in: state.devices.microphones)).tag(String?.none)
                    ForEach(state.devices.microphones) { mic in
                        Text(mic.name).tag(Optional(mic.id))
                    }
                }
                .labelsHidden()
                .frame(maxWidth: 190)
                .disabled(!state.prefs.microphoneEnabled || state.isBusy)
            }
            .disabled(state.isBusy)
            permissionHint(state.microphonePermission, pane: .microphone, name: "Microphone")

            Toggle("System audio (what you hear)", isOn: Binding(
                get: { state.prefs.systemAudioEnabled },
                set: { on in state.setSystemAudioEnabled(on) }))
                .toggleStyle(.switch)
                .controlSize(.small)
                .disabled(state.isBusy)
        }
    }

    @ViewBuilder
    private func permissionHint(_ permission: PermissionState, pane: Permissions.SettingsPane, name: String) -> some View {
        if permission == .denied {
            HStack(spacing: 6) {
                Text("\(name) access is off.")
                Button("Open System Settings") { Permissions.openSystemSettings(pane) }
                    .buttonStyle(.link)
            }
            .font(.caption)
            .foregroundStyle(.orange)
        }
    }

    private func defaultLabel(for id: String?, in devices: [MediaDevice]) -> String {
        if let name = devices.first(where: { $0.id == id })?.name {
            return "Default (\(name))"
        }
        return "Default"
    }

    @ViewBuilder
    private var actionSection: some View {
        switch state.phase {
        case .idle:
            Button {
                Task { await state.startRecording() }
            } label: {
                Label("Start Recording", systemImage: "record.circle")
                    .frame(maxWidth: .infinity)
            }
            .keyboardShortcut(.defaultAction)
            .buttonStyle(.borderedProminent)
            .tint(.red)
            .disabled(!state.canRecord)
            if !state.canUpload {
                signInHint
            }
            if let last = state.lastRecording {
                lastRecordingRow(last)
            }
        case .preparing:
            HStack { ProgressView().controlSize(.small); Text("Preparing…") }
        case .countdown(let n):
            HStack {
                Text("Starting in \(n)…").font(.headline)
                Spacer()
                Button("Cancel") { state.cancelCountdown() }
            }
        case .recording:
            HStack {
                Image(systemName: "record.circle.fill").foregroundStyle(.red)
                Text(state.elapsedText).font(.system(.title3, design: .monospaced))
                Spacer()
                Button("Stop") { Task { await state.stopRecording() } }
                    .buttonStyle(.borderedProminent)
            }
        case .saving:
            HStack { ProgressView().controlSize(.small); Text("Saving…") }
        case .saved(let url):
            VStack(alignment: .leading, spacing: 8) {
                Label("Saved \(url.lastPathComponent)", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .lineLimit(2)
                HStack {
                    if state.canUpload {
                        Button("Upload") { state.uploadLastRecording() }
                    } else {
                        uploadBlockerButton(label: "Sign In to Upload")
                    }
                    Button("Reveal in Finder") { state.revealLastRecording() }
                    Button("Discard") { state.discardLastRecording() }
                    Spacer()
                    Button("Done") { state.dismissResult() }
                }
                .controlSize(.small)
                if let error = state.signInError {
                    Text(error).font(.caption).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
                }
            }
        case .uploading(let file):
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "arrow.up.circle").foregroundStyle(.blue)
                    Text("Uploading to VideoPress… \(state.uploadPercentText)")
                    Spacer()
                    Button("Cancel") { state.cancelUpload() }.controlSize(.small)
                }
                ProgressView(value: state.uploadProgress)
                titleField(placeholder: file.deletingPathExtension().lastPathComponent)
                Text("The link goes to your clipboard the moment the upload finishes.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        case .uploaded(let file, let result):
            VStack(alignment: .leading, spacing: 8) {
                Label(state.prefs.copyLinkAfterUpload ? "Link copied to clipboard" : "Uploaded to VideoPress",
                      systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text(result.shareURL.absoluteString)
                    .font(.caption)
                    .textSelection(.enabled)
                    .lineLimit(1)
                    .truncationMode(.middle)
                HStack {
                    titleField(placeholder: file.deletingPathExtension().lastPathComponent)
                    Button("Save Title") { Task { await state.saveUploadedTitle() } }.controlSize(.small)
                }
                HStack {
                    Button("Open") { state.openShareLink() }
                    Button("Copy Link") { state.copyShareLink() }
                    if FileManager.default.fileExists(atPath: file.path) {
                        Button("Reveal File") { state.revealLastRecording() }
                    }
                    Spacer()
                    Button("Done") { state.dismissResult() }
                }
                .controlSize(.small)
                Text("Playback starts within a minute at low quality; VideoPress adds the full-quality version a few minutes later.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        case .uploadFailed(_, let message):
            VStack(alignment: .leading, spacing: 8) {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    if state.canUpload {
                        Button("Retry Upload") { state.uploadLastRecording() }
                    } else {
                        uploadBlockerButton(label: "Sign In")
                    }
                    Button("Reveal File") { state.revealLastRecording() }
                    Spacer()
                    Button("Dismiss") { state.dismissResult() }
                }
                .controlSize(.small)
            }
        case .failed(let message):
            VStack(alignment: .leading, spacing: 8) {
                Label(message, systemImage: "xmark.octagon.fill")
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Dismiss") { state.dismissResult() }.controlSize(.small)
            }
        }
    }

    private var signInHint: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: "person.crop.circle.badge.exclamationmark")
                if !state.hasClientSecret {
                    Text("This build cannot sign in to WordPress.com (no client secret). Recordings stay local.")
                } else if state.account == nil {
                    Text("Sign in to WordPress.com to get a share link after each recording.")
                    Spacer()
                    Button(state.isSigningIn ? "Waiting…" : "Sign In") { state.signIn() }
                        .buttonStyle(.link)
                        .disabled(state.isSigningIn)
                } else if state.needsReSignIn {
                    Text("Sign in again so Loominate can list your sites.")
                    Spacer()
                    Button(state.isSigningIn ? "Waiting…" : "Sign In") { state.signIn() }
                        .buttonStyle(.link)
                        .disabled(state.isSigningIn)
                } else {
                    Text(state.isLoadingSites ? "Loading your sites…" : "Choose which site uploads go to.")
                    Spacer()
                    Button("Choose Site") { state.openSettings() }
                        .buttonStyle(.link)
                }
            }
            if state.isSigningIn {
                HStack(spacing: 6) {
                    Text("Approve Loominate in your browser.")
                    Button("Cancel") { state.cancelSignIn() }.buttonStyle(.link)
                }
            }
            if let error = state.signInError {
                Text(error).foregroundStyle(.red)
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
    }

    /// Whatever stands between the user and an upload: sign-in, a fresh sign-in, or picking a site.
    @ViewBuilder
    private func uploadBlockerButton(label: String) -> some View {
        if !state.hasClientSecret {
            EmptyView()
        } else if state.account == nil || state.needsReSignIn {
            Button(state.isSigningIn ? "Waiting for browser…" : label) { state.signIn() }
                .disabled(state.isSigningIn)
        } else {
            Button("Choose Site…") { state.openSettings() }
        }
    }

    private func titleField(placeholder: String) -> some View {
        HStack(spacing: 4) {
            if !state.prefs.titlePrefix.isEmpty {
                Text(state.prefs.titlePrefix).foregroundStyle(.secondary)
            }
            TextField(placeholder, text: $state.uploadTitle)
                .textFieldStyle(.roundedBorder)
        }
        .font(.caption)
    }

    private func lastRecordingRow(_ url: URL) -> some View {
        HStack(spacing: 6) {
            Text("Last: \(url.lastPathComponent)").lineLimit(1).truncationMode(.middle)
            Spacer()
            Button("Reveal") { state.revealLastRecording() }.buttonStyle(.link)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }
}

struct MenuBarLabel: View {
    let state: AppState

    /// The Loominate glyph as a template image, so macOS tints it for light and dark menu bars.
    private static let glyph: NSImage? = {
        guard let image = Bundle.main.image(forResource: "MenuBarIcon") else { return nil }
        image.isTemplate = true
        return image
    }()

    var body: some View {
        if state.isRecording {
            HStack(spacing: 3) {
                Image(systemName: "record.circle.fill")
                Text(state.elapsedText)
            }
        } else if state.isUploading {
            HStack(spacing: 3) {
                Image(systemName: "arrow.up.circle")
                Text(state.uploadPercentText)
            }
        } else if let glyph = Self.glyph {
            Image(nsImage: glyph)
        } else {
            Image(systemName: "record.circle")
        }
    }
}
