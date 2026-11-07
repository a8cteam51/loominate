import SwiftUI

struct SettingsView: View {
    @Bindable var state: AppState

    var body: some View {
        Form {
            Section("Video") {
                Picker("Quality", selection: $state.prefs.quality) {
                    ForEach(QualityPreset.allCases) { Text($0.label).tag($0) }
                }
                Picker("Frame rate", selection: $state.prefs.frameRate) {
                    ForEach(FrameRate.allCases) { Text($0.label).tag($0) }
                }
                Picker("Resolution", selection: $state.prefs.scale) {
                    ForEach(CaptureScale.allCases) { Text($0.label).tag($0) }
                }
                Picker("Codec", selection: $state.prefs.codec) {
                    ForEach(VideoCodecChoice.allCases) { Text($0.label).tag($0) }
                }
                Toggle("Show mouse cursor", isOn: $state.prefs.showsCursor)
                Text(bitrateHint).font(.caption).foregroundStyle(.secondary)
            }
            Section("Camera bubble") {
                Picker("Size", selection: $state.prefs.bubbleSize) {
                    ForEach(BubbleSize.allCases) { Text($0.label).tag($0) }
                }
                Picker("Position", selection: $state.prefs.bubbleCorner) {
                    ForEach(BubbleCorner.allCases) { Text($0.label).tag($0) }
                }
                Text("You can also drag the self-view; it snaps to the nearest corner.").font(.caption).foregroundStyle(.secondary)
            }
            Section("Recording") {
                Picker("Countdown", selection: $state.prefs.countdownSeconds) {
                    Text("Off").tag(0)
                    Text("3 seconds").tag(3)
                    Text("5 seconds").tag(5)
                }
                Toggle("Reveal in Finder when saved", isOn: $state.prefs.revealInFinderAfterSave)
                LabeledContent("Save to") {
                    HStack {
                        Text(state.prefs.outputFolder.path(percentEncoded: false))
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Button("Choose…") { state.chooseOutputFolder() }
                    }
                }
            }
            Section("WordPress.com account") {
                if let account = state.account {
                    LabeledContent("Signed in as", value: account.label)
                    LabeledContent("Uploads go to", value: WPComConfig.siteName)
                    Button("Sign Out") { state.signOut() }
                } else if state.isSigningIn {
                    HStack {
                        ProgressView().controlSize(.small)
                        Text("Waiting for you to approve Loominate in your browser…")
                        Spacer()
                        Button("Cancel") { state.cancelSignIn() }
                    }
                } else {
                    Text("Sign in once to upload recordings to VideoPress on \(WPComConfig.siteName). The sign-in is kept in your Keychain.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("Sign in with WordPress.com") { state.signIn() }
                        .disabled(!state.hasClientSecret)
                    if !state.hasClientSecret {
                        Text(WPComError.missingClientSecret.localizedDescription)
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
                if let error = state.signInError {
                    Text(error).font(.caption).foregroundStyle(.red)
                }
            }
            Section("Upload") {
                Toggle("Upload automatically when a recording stops", isOn: $state.prefs.autoUpload)
                Text("Off: each recording is saved locally and you choose Upload, Reveal, or Discard.").font(.caption).foregroundStyle(.secondary)
                TextField("Title prefix", text: $state.prefs.titlePrefix, prompt: Text("e.g. Partner: "))
                Toggle("Copy the link when the upload finishes", isOn: $state.prefs.copyLinkAfterUpload)
                Toggle("Show a notification when the link is ready", isOn: $state.prefs.notifyWhenUploaded)
                Toggle("Delete the local file after a successful upload", isOn: $state.prefs.deleteLocalAfterUpload)
            }
        }
        .formStyle(.grouped)
        .frame(width: 440)
        .onChange(of: state.prefs) { _, newValue in newValue.save() }
        .onChange(of: state.prefs.bubbleSize) { _, _ in state.applyBubbleLayout() }
        .onChange(of: state.prefs.bubbleCorner) { _, _ in state.applyBubbleLayout() }
    }

    private var bitrateHint: String {
        let mbps = Double(state.prefs.videoBitrate(width: 1920, height: 1080)) / 1_000_000
        return String(format: "About %.1f Mbps at 1080p, roughly %.0f MB per 5 minutes of video.", mbps, mbps * 300 / 8)
    }
}
