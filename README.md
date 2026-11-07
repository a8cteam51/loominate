# Loominate

A small native macOS menu bar app that records your screen the way Loom does: a display or
a single window, optional system audio (what you hear), optional microphone, and an optional
circular camera bubble. Recordings land in `~/Movies/Loominate` as compact H.264 `.mp4` files
with one mixed audio track, ready to upload anywhere.

When you stop a recording, a small panel offers **Upload & Copy Link**, **Reveal**, or
**Discard**. Upload sends it to VideoPress on specialprojects.automattic.com and puts the share
link on your clipboard; Discard moves an outtake to the Trash. Nothing leaves your Mac unless you
ask. Recording works without signing in; the file just stays local.

## Requirements

- macOS 26 or later on Apple Silicon (ScreenCaptureKit does all capture; nothing third-party).
- Swift 6.4 Command Line Tools. Full Xcode is not needed to build or run locally.

## Build and run

```bash
make build        # swift build + assemble build/Loominate.app (debug)
make run          # build, then open the app (it appears in the menu bar, no Dock icon)
make release      # optimized build
make clean
```

Always run the app from `build/Loominate.app` via `open` (which `make run` does). Running the
bare binary from a terminal makes the terminal the responsible process for permissions, and a
binary outside the bundle has no `Info.plist`, so camera or microphone access crashes it.

### Keep permissions across rebuilds

macOS ties Screen Recording, Microphone, Camera and Keychain grants to the app's code
signature. An ad-hoc signature changes on every build, so the grants silently stop matching:
System Settings still shows the permission as enabled, but the app is denied, and the Keychain
asks for your password again. Create a self-signed signing certificate once:

```bash
Scripts/make-dev-cert.sh            # creates "Loominate Dev" in your login keychain
make build
```

`Scripts/bundle.sh` finds that certificate (or an older "Recorder Dev") by itself; set
`SIGN_IDENTITY` only to override it. If a build was ever made ad-hoc, reset the stale grants once
and re-approve with the properly signed app:

```bash
tccutil reset All com.automattic.loominate
make run
```

### The WordPress.com client secret (builders only)

Uploads use a WordPress.com OAuth app (client ID 152440). Its secret is in the team's 1Password
and is baked into the built app, never into the repo:

```bash
mkdir -p .secrets
echo 'WPCOM_CLIENT_SECRET=paste-it-here' > .secrets/wpcom.env   # gitignored
make build
```

`Scripts/bundle.sh` writes it into the built bundle's `Info.plist` before signing (or reads
`WPCOM_CLIENT_SECRET` from the environment). A build without it still records, but Settings
shows that sign-in is unavailable. People who receive a built app never need the secret.

## First launch

1. Click the record icon in the menu bar. The panel asks for Screen Recording permission.
2. Click **Request Permission**, allow it in System Settings, then quit and reopen Loominate.
3. Turn on Camera or Microphone in the panel; macOS asks for each the first time.
4. Click **Sign In** (panel or Settings → WordPress.com account). Your browser opens a
   WordPress.com approval page; click Approve and come back. This is a one-time step per Mac:
   the sign-in lives in your Keychain and only needs redoing if WordPress.com rejects it.
   You need at least the Author role on the Special Projects site.
5. The first upload after a new build may show a Keychain dialog asking whether Loominate may
   use the saved sign-in. Choose **Always Allow**; the app reads the item once per launch.

## Using it

- **Source**: Screen (choose a display if you have several) or Window (pick from the list).
- **Camera**: on/off plus which camera. A floating circular self-view appears so you can
  check framing. It is never captured; the recording gets its own bubble drawn in the corner.
- **Microphone**: on/off plus which mic. "Default" follows System Settings → Sound live.
- **System audio**: records everything playing through the Mac, including headphones.
- **Start Recording**: a 3-2-1 countdown, then the menu bar shows a red dot and timer and a
  small floating Stop control appears. Neither shows up in the recording.
- **Stop**: the file is finalized (a few seconds) and a floating panel appears with the file
  size, a title field, and Upload & Copy Link / Reveal / Discard. Outtakes: hit Discard (the
  file goes to the Trash) and record again.
- **Upload**: the menu bar shows the percentage. When it finishes, the `videopress.com/v/…`
  link is on your clipboard and a notification says so. Playback starts once VideoPress finishes
  processing, usually within a minute. A title typed before or during the upload is applied at
  the end.
- Not signed in: the panel offers Sign In instead of Upload. Upload failed: the local file is
  kept and the panel offers Retry.
- Settings has an "Upload automatically when a recording stops" switch for people who want the
  old Loom behaviour; it is off by default.

Settings (gear icon): quality, frame rate, 1x or 2x resolution, H.264 or HEVC, bubble size and
corner, countdown length, cursor, output folder, reveal in Finder; WordPress.com account (sign in
and out); upload on/off, title prefix (for example `Partner: `, to keep clips findable in the
site's VideoPress library), copy link, notification, delete local file after upload.

## File sizes

Target bitrates from the quality heuristic at 1080p: Low about 1.5 Mbps, Medium about 2.5 Mbps,
High about 4.3 Mbps. HEVC targets 60% of those. Real files are usually smaller: the capture only
emits frames when the screen changes, so a mostly static screen at Medium measured about
1.0 to 1.2 Mbps in testing (around 45 MB for five minutes), and 2x resolution roughly doubles that.
With the camera bubble on, frames are written at a constant rate, so expect numbers closer to the
targets.

## How it works

```
ScreenCaptureKit (screen + system audio + mic) ─► FramePacer ─► BubbleCompositor ─► AVAssetWriter (.mov)
AVCaptureSession (camera) ──latest frame──────────┘                                          │ stop
                                        Mixdown: video passthrough, audio mixed to one AAC track ─► .mp4
                                                                                                    │
     WordPress.com OAuth token (Keychain) ─► upload token ─► resumable tus upload (10 MB chunks) ─► VideoPress
                                                                       share link ─► clipboard + notification
```

- Sign-in is the WordPress.com authorization-code flow with a loopback redirect: the app listens on
  127.0.0.1:52631 for the browser's callback, exchanges the code, and stores the token in the login
  Keychain. The token is scoped to the Special Projects site only.
- The upload is the same resumable protocol Jetpack's own VideoPress uploader uses; interrupted
  uploads resume from the server's offset.

- Display recordings exclude every window of this app through the content filter.
- While recording, the intermediate `.mov` is written in fragments, so a crash still leaves a
  playable file next to where the `.mp4` would have been.
- System audio and mic are recorded as separate tracks and mixed once at stop (mic 1.0,
  system 0.8), because browsers and transcoders only play a file's first audio track.

## Command-line test modes

Useful for checking the pipeline without clicking through the UI. They run under the
terminal's permissions, so the terminal app needs Screen Recording (and Microphone) access.

```bash
R=build/Loominate.app/Contents/MacOS/Loominate
$R --devices                                   # cameras, mics, permission state
$R --probe ~/Movies/Loominate/some.mp4          # tracks, codecs, bitrate (no ffprobe needed)
$R --record --seconds 10 --out /tmp/test.mp4   # main display, system audio + default mic
$R --record --seconds 5 --window "Safari" --fake-camera --bubble-corner topRight
$R --record --seconds 5 --no-mic --no-system-audio --fps 60 --scale 2 --quality high --codec hevc
```

`open build/Loominate.app --args --auto-record 5` launches the real app and drives the UI path
(countdown, HUD, menu bar timer) for a 5-second recording without any clicks.

`--fake-camera` feeds a synthetic animated image to the bubble so the compositor can be tested
without camera permission.

WordPress.com commands (run through the bundle; they share the Keychain item with the app):

```bash
$R --login                 # opens the browser; add --no-browser to print the URL instead
$R --whoami
$R --logout
$R --upload ~/Movies/Loominate/some.mp4 --title "Partner: Setting up the dashboard"
```

`--upload` prints progress on stderr and only the share link on stdout, so it works in scripts
(exit 2 = not signed in, 3 = sign-in rejected). With a signed-in account,
`--auto-record 5 --upload` goes all the way to a share link.

## Distribution

`make dmg` packages the current build into `dist/Loominate-<version>.dmg`, a disk image that
opens to the usual "drag Loominate into Applications" window (`Scripts/make-dmg.sh`; the window
layout is set through Finder scripting, so macOS asks once to let your terminal control Finder).

A DMG built with the dev certificate is fine for your own Mac but will be blocked by Gatekeeper
on anyone else's. Shipping to the team needs, one time:

1. A **Developer ID Application** certificate from Automattic's Apple Developer team, installed
   in the builder's keychain.
2. Notarization credentials stored for `notarytool`, for example
   `xcrun notarytool store-credentials loominate --apple-id … --team-id … --password <app-specific>`.

Then `SIGN_IDENTITY="Developer ID Application: …" make dist` builds with the hardened runtime
and `Scripts/Loominate.entitlements`, notarizes and staples the app and the DMG, and leaves the
result in `dist/`. Recipients double-click the DMG, drag, and open the app with no warnings.
No Xcode is required: `notarytool` and `stapler` ship with the Command Line Tools.

## Icons

`Assets/AppIcon-1024.png` (the full-bleed logomark) and `Assets/loominate-menubar.svg` (the
monochrome glyph) are the sources. `Scripts/make-icons.sh` composes the logomark onto the macOS
rounded tile, builds `AppIcon.icns`, and rasterizes the menu bar template at 1x and 2x. The
generated files are committed, so only someone changing the artwork needs ImageMagick
(`brew install imagemagick`).

## Known limitations

- Record and Stop only. No pause, trim, or region selection yet.
- Uploaded videos land in the site's VideoPress library alongside everything else; use the title
  prefix to keep them findable. VideoPress playlists have an admin-only API and are not used.
- Uploads go to one fixed site (blog ID 236976534, in `WPComConfig.swift`).
- A fresh VideoPress link plays at low quality first; the full-quality rendition arrives a few
  minutes later. Turning on "Display higher quality video by default" in the site's
  Settings → Media makes the player prefer the best rendition that exists.
- If a captured window is resized mid-recording, its content scales inside the original frame.
- macOS periodically re-confirms that the app may record the screen; that is expected for any
  app using ScreenCaptureKit outside Apple's own picker.
- Builds use Swift language mode 5. SwiftUI's `@State` is macro-backed in the macOS 26 SDK and
  that macro plugin is not shipped with Command Line Tools, so the code uses plain stored
  properties and `@Observable`/`@Bindable` instead.
- Closing the menu bar panel when a recording starts relies on hiding the app's untitled
  windows; the Settings window (which has a title) stays open.
