import AppKit
import SwiftUI

/// Floating panel shown after a recording stops: upload, reveal, or discard, then the link.
final class ResultHUD: NSPanel {
    init(state: AppState) {
        let size = NSSize(width: 420, height: 92)
        super.init(contentRect: NSRect(origin: .zero, size: size),
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered,
                   defer: false)
        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isMovableByWindowBackground = true
        hidesOnDeactivate = false
        let hosting = NSHostingView(rootView: ResultHUDView(state: state))
        hosting.frame = NSRect(origin: .zero, size: size)
        hosting.autoresizingMask = [.width, .height]
        contentView = hosting
        setContentSize(size)
        if let screen = NSScreen.main {
            let visible = screen.visibleFrame
            setFrameOrigin(NSPoint(x: visible.midX - size.width / 2, y: visible.maxY - size.height - 12))
        }
    }

    override var canBecomeKey: Bool { true }   // the title field needs keyboard focus
    override var canBecomeMain: Bool { false }
}

private struct ResultHUDView: View {
    @Bindable var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            switch state.phase {
            case .saving:
                HStack(spacing: 8) { ProgressView().controlSize(.small); Text("Saving recording…") }
            case .saved(let url):
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    Text("Recording saved").fontWeight(.medium)
                    Text(sizeText(url)).foregroundStyle(.secondary)
                    Spacer()
                    Button("Discard") { state.discardLastRecording() }
                    Button("Reveal") { state.revealLastRecording() }
                    if state.canUpload {
                        Button("Upload & Copy Link") { state.uploadLastRecording() }
                            .buttonStyle(.borderedProminent)
                            .keyboardShortcut(.defaultAction)
                    } else if state.hasClientSecret && (state.account == nil || state.needsReSignIn) {
                        Button(state.isSigningIn ? "Waiting…" : "Sign In to Upload") { state.signIn() }
                            .disabled(state.isSigningIn)
                    } else if state.hasClientSecret {
                        Button("Choose Site…") { state.openSettings() }
                    }
                }
                titleRow(placeholder: url.deletingPathExtension().lastPathComponent)
            case .uploading:
                HStack(spacing: 8) {
                    Image(systemName: "arrow.up.circle").foregroundStyle(.blue)
                    Text("Uploading… \(state.uploadPercentText)")
                    ProgressView(value: state.uploadProgress).frame(maxWidth: 160)
                    Spacer()
                    Button("Cancel") { state.cancelUpload() }
                }
                Text("The link goes to your clipboard when this finishes.").foregroundStyle(.secondary)
            case .uploaded(_, let result):
                HStack(spacing: 8) {
                    Image(systemName: "link.circle.fill").foregroundStyle(.green)
                    Text(state.prefs.copyLinkAfterUpload ? "Link copied" : "Uploaded").fontWeight(.medium)
                    Text(result.shareURL.absoluteString).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                    Spacer()
                    Button("Open") { state.openShareLink() }
                    Button("Copy") { state.copyShareLink() }
                    Button("Done") { state.dismissResult() }.keyboardShortcut(.defaultAction)
                }
                Text("Playback starts within a minute at low quality; VideoPress adds the full-quality version a few minutes later.")
                    .foregroundStyle(.secondary)
            case .uploadFailed(_, let message):
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    Text(message).lineLimit(2)
                    Spacer()
                    if state.canUpload { Button("Retry") { state.uploadLastRecording() } }
                    Button("Reveal") { state.revealLastRecording() }
                    Button("Dismiss") { state.dismissResult() }
                }
            case .failed(let message):
                HStack(spacing: 8) {
                    Image(systemName: "xmark.octagon.fill").foregroundStyle(.red)
                    Text(message).lineLimit(2)
                    Spacer()
                    Button("Dismiss") { state.dismissResult() }
                }
            default:
                EmptyView()
            }
        }
        .font(.callout)
        .controlSize(.small)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(.white.opacity(0.15)))
    }

    private func titleRow(placeholder: String) -> some View {
        HStack(spacing: 6) {
            Text("Title").foregroundStyle(.secondary)
            if !state.prefs.titlePrefix.isEmpty {
                Text(state.prefs.titlePrefix).foregroundStyle(.secondary)
            }
            TextField(placeholder, text: $state.uploadTitle)
                .textFieldStyle(.roundedBorder)
        }
    }

    private func sizeText(_ url: URL) -> String {
        guard let bytes = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.doubleValue else { return "" }
        return String(format: "%.1f MB", bytes / 1_000_000)
    }
}
