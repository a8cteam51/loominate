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
                    if state.needsReSignIn {
                        Text("Sign in again so Loominate can list your sites and let you choose where uploads go.")
                            .font(.caption)
                            .foregroundStyle(.orange)
                        Button(state.isSigningIn ? "Waiting for your browser…" : "Sign In Again") { state.signIn() }
                            .disabled(state.isSigningIn || !state.hasClientSecret)
                    } else {
                        if state.eligibleSites.count > 12 {
                            TextField("Find a site", text: $state.siteFilter,
                                      prompt: Text("Type part of a site's name or address to shorten the list"))
                                .textFieldStyle(.roundedBorder)
                        }
                        Picker("Upload to", selection: Binding(
                            get: { state.account?.siteID },
                            set: { id in state.selectSite(state.sites.first { $0.id == id }) })) {
                            if state.account?.siteID == nil {
                                Text("Choose a site…").tag(Int?.none)
                            } else if let id = state.account?.siteID, !state.filteredEligibleSites.contains(where: { $0.id == id }) {
                                Text(state.account?.siteLabel ?? "Selected site").tag(Optional(id))
                            }
                            ForEach(state.filteredEligibleSites) { site in
                                Text(site.label).tag(Optional(site.id))
                            }
                        }
                        if !state.siteFilter.isEmpty && state.filteredEligibleSites.isEmpty {
                            Text("No site with VideoPress matches “\(state.siteFilter)”.").font(.caption).foregroundStyle(.secondary)
                        }
                        HStack(spacing: 10) {
                            Button("Refresh Sites") { Task { await state.loadSites() } }
                                .disabled(state.isLoadingSites)
                            if state.isLoadingSites {
                                ProgressView().controlSize(.small)
                            } else if !state.sites.isEmpty {
                                let eligible = state.eligibleSites.count
                                Text(eligible == state.sites.count ? "All \(state.sites.count) of your sites have VideoPress."
                                     : "\(eligible) of your \(state.sites.count) sites have VideoPress and can take uploads.")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        if !state.sites.isEmpty && state.eligibleSites.isEmpty {
                            Text("None of your sites can take uploads. You need a WordPress.com plan that includes VideoPress, or the Jetpack VideoPress plan.")
                                .font(.caption).foregroundStyle(.orange)
                        }
                        Text("Share links play for anyone unless the site restricts VideoPress to members.")
                            .font(.caption).foregroundStyle(.secondary)
                        if let error = state.sitesError {
                            Text(error).font(.caption).foregroundStyle(.red)
                        }
                    }
                    Button("Sign Out") { state.signOut() }
                } else if state.isSigningIn {
                    HStack {
                        ProgressView().controlSize(.small)
                        Text("Waiting for you to approve Loominate in your browser…")
                        Spacer()
                        Button("Cancel") { state.cancelSignIn() }
                    }
                } else {
                    Text("Sign in once to upload recordings to VideoPress on one of your WordPress sites. The sign-in is kept in your Keychain.")
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
            Section("Updates") {
                LabeledContent("Version", value: state.updates.versionLabel)
                Toggle("Check for updates automatically", isOn: $state.prefs.checkForUpdatesAutomatically)
                HStack(spacing: 10) {
                    Button("Check Now") { Task { await state.updates.check(userInitiated: true) } }
                        .disabled(state.updates.isWorking)
                    if state.updates.phase == .checking {
                        ProgressView().controlSize(.small)
                    }
                    Text(state.updates.statusText).font(.caption).foregroundStyle(.secondary)
                }
                if let update = state.updates.availableUpdate {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Loominate \(update.version) is available")
                            .font(.subheadline.weight(.semibold))
                        if !update.notes.isEmpty {
                            ScrollView {
                                Text(update.notes)
                                    .font(.caption)
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .frame(maxHeight: 110)
                        }
                        switch state.updates.phase {
                        case .downloading(let fraction):
                            ProgressView(value: fraction) { Text("Downloading…").font(.caption) }
                        case .verifying:
                            ProgressView { Text("Checking the download…").font(.caption) }
                        case .installing:
                            ProgressView { Text("Installing…").font(.caption) }
                        default:
                            HStack(spacing: 10) {
                                // When blocked, the reason and the reinstall command appear below instead.
                                if !state.updates.isBlocked {
                                    Button("Install and Relaunch") { state.updates.install() }
                                        .buttonStyle(.borderedProminent)
                                        .disabled(state.isBusy)
                                }
                                if state.updates.skippedVersion == update.version {
                                    Button("Stop Skipping") { state.updates.unskip() }
                                } else {
                                    Button("Skip This Version") { state.updates.skipAvailableVersion() }
                                }
                                if update.releaseNotesURL != nil {
                                    Button("Release Notes") { state.updates.openReleaseNotes() }
                                        .buttonStyle(.link)
                                }
                            }
                            if state.isBusy && !state.updates.isBlocked {
                                Text("Finish the recording or upload first.").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                if case .failed(let message) = state.updates.phase {
                    Text(message).font(.caption).foregroundStyle(.red)
                }
                if case .blocked(let message) = state.updates.phase {
                    Text(message).font(.caption).foregroundStyle(.orange)
                    HStack(spacing: 8) {
                        Text(state.updates.installCommand)
                            .font(.caption.monospaced())
                            .textSelection(.enabled)
                            .lineLimit(2)
                        Button("Copy") { state.updates.copyInstallCommand() }
                            .controlSize(.small)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 440)
        .onAppear { Task { await state.loadSitesIfNeeded() } }
        .onChange(of: state.prefs) { _, newValue in newValue.save() }
        .onChange(of: state.prefs.bubbleSize) { _, _ in state.applyBubbleLayout() }
        .onChange(of: state.prefs.bubbleCorner) { _, _ in state.applyBubbleLayout() }
    }

    private var bitrateHint: String {
        let mbps = Double(state.prefs.videoBitrate(width: 1920, height: 1080)) / 1_000_000
        return String(format: "About %.1f Mbps at 1080p, roughly %.0f MB per 5 minutes of video.", mbps, mbps * 300 / 8)
    }
}
