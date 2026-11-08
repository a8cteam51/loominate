# Developing Loominate

Loominate is a SwiftUI menu bar app built with SwiftPM and a shell script that assembles the
`.app` bundle. No Xcode is required; the Swift 6.4 Command Line Tools are enough.

## Build and run

```bash
make build        # swift build + assemble build/Loominate.app (debug)
make run          # build, then open the app
make release      # optimized build
make dmg          # drag-to-Applications disk image in dist/
make clean
```

Always launch the app from the bundle (`make run` does), never the bare binary: the bundle's
`Info.plist` carries the camera and microphone usage strings and the client secret, and macOS ties
permissions to the bundle's code identity.

### The signing certificate

macOS ties Screen Recording, Microphone, Camera and Keychain grants to the app's code signature. An
ad-hoc signature changes on every build and silently breaks those grants. Create a self-signed
signing certificate once:

```bash
Scripts/make-dev-cert.sh      # creates "Loominate Dev" in your login keychain
make build                    # Scripts/bundle.sh finds and uses it automatically
```

If a build was ever made ad-hoc, reset the stale grants and re-approve with the signed app:

```bash
tccutil reset All com.automattic.loominate
make run
```

For the person who publishes releases this certificate matters more: it is also the release
identity. The self-updater only installs a build whose signature satisfies the running app's
designated requirement, which names this certificate's leaf. Every release must therefore be signed
with the same certificate, forever, or installed copies stop updating. Export it from Keychain
Access as a `.p12` and keep it somewhere safe (1Password). If it is ever lost, see "Changing the
signing identity" below.

### The WordPress.com client secret

Uploads use a WordPress.com OAuth app. Its secret is never in the repo: `Scripts/bundle.sh` reads
`.secrets/wpcom.env` (gitignored) or `WPCOM_CLIENT_SECRET` and writes it into the built bundle's
`Info.plist` before signing. A build without it still records, but Settings shows sign-in as
unavailable.

The client ID in `WPComConfig.swift` belongs to the WordPress.com Special Projects team. To build
from source for yourself, register your own OAuth app at developer.wordpress.com/apps (type Web,
redirect URL `http://127.0.0.1:52631/callback`), set its client ID in `WPComConfig.swift`, and put
the secret in `.secrets/wpcom.env`:

```
WPCOM_CLIENT_SECRET=…
```

Sign-in asks for the `global` scope so the app can list every site you belong to; the site picker
only offers sites where you can upload files and VideoPress is active (the same rule Calypso uses:
`videopress_enabled`, or the `videopress` Jetpack module). WordPress.com Simple, Atomic and
self-hosted Jetpack sites all upload through the same two calls.

## How it works

```
ScreenCaptureKit (screen + system audio + mic) ─► FramePacer ─► BubbleCompositor ─► AVAssetWriter (.mov)
AVCaptureSession (camera) ──latest frame──────────┘                                          │ stop
                                        Mixdown: video passthrough, audio mixed to one AAC track ─► .mp4
                                                                                                    │
     WordPress.com OAuth token (Keychain) ─► upload token for the chosen site ─► resumable tus upload ─► VideoPress
                                                                       share link ─► clipboard + notification

     GitHub Releases ─► latest.json (Ed25519-signed) ─► newer? ─► zip (hash pinned) ─► same code identity? ─► atomic swap ─► relaunch
```

- Capture is ScreenCaptureKit; the app's own windows are excluded through the content filter.
- The camera bubble is composited into each frame before encoding, so it works for window captures too.
- System audio and mic are recorded as separate tracks and mixed once at stop, because browser
  players only use a file's first audio track. The intermediate `.mov` is written in fragments so a
  crash still leaves a playable file.
- Sign-in is the WordPress.com authorization-code flow with a loopback listener on 127.0.0.1:52631.
  The token is stored in the login Keychain and read once per launch.
- Uploads use the same resumable protocol as Jetpack's VideoPress uploader and resume from the
  server's offset after a failure.
- Updates: see below.

Settings live in `UserDefaults`; a plain-text session log is written to
`~/Library/Logs/Loominate/loominate.log`.

## Headless test modes

The bundle's binary doubles as a CLI, which is how the pipeline is exercised without clicking.
`--help` lists everything.

```bash
R=build/Loominate.app/Contents/MacOS/Loominate
$R --devices                                   # cameras, mics, permission state
$R --probe ~/Movies/Loominate/some.mp4         # tracks, codecs, bitrate
$R --record --seconds 10 --out /tmp/test.mp4   # main display, system audio + default mic
$R --record --seconds 5 --window "Safari" --fake-camera --bubble-corner topRight
$R --record --seconds 4 --fake-camera --move-bubble 2:topRight   # simulates dragging the bubble mid-recording
$R --login                                     # browser sign-in; --no-browser prints the URL
$R --whoami
$R --sites                                     # every site you belong to and which can take uploads
$R --select-site example.wordpress.com         # where uploads go (id or URL)
$R --upload ~/Movies/Loominate/some.mp4 --title "Example" [--site other.example]
$R --check-update                              # fetch + verify the feed, compare with this build
$R --install-update [--no-launch]              # install the newest release over this bundle
open build/Loominate.app --args --auto-record 5 --upload   # drives the real UI end to end
```

Recording commands run under the terminal's permissions, so the terminal app needs Screen Recording
(and Microphone) access. `--fake-camera` feeds a synthetic image to the bubble so the compositor can
be tested without camera permission.

### Recording Loominate itself

Display captures normally leave out every window Loominate owns, so a demo of the app can't be
recorded with the app. A hidden switch turns that off:

```bash
defaults write com.automattic.loominate recordOwnWindows -bool true    # then quit and reopen the app
defaults delete com.automattic.loominate recordOwnWindows              # back to normal
```

With it on, the panel, countdown, floating control, result card and Settings all show up in the
video, and the camera bubble is not composited for display captures because the on-screen self-view
is in the recording already. `--record --include-self` does the same for one headless run.

## Updates

Installed copies update themselves. The design assumes no Developer ID: files the app (or `curl`)
downloads carry no quarantine flag, so Gatekeeper never sees them, and trust comes from two checks
of our own instead.

- **The feed** is one asset on each GitHub Release, `latest.json`, fetched from
  `https://github.com/a8cteam51/loominate/releases/latest/download/latest.json` (a plain redirect,
  no API rate limit). It is an envelope: `payload` (base64 JSON) plus an Ed25519 `signature` over
  exactly those bytes, made by `Scripts/sign-manifest.sh`. The payload names the version, build
  number, minimum macOS, the zip's URL, SHA-256 and size, and the release notes. One signature binds
  all of it, so a swapped zip fails the hash and an edited manifest fails the signature. The public
  keys live in `Sources/Loominate/Update/UpdateConfig.swift`; the private key is
  `.secrets/update-signing-key` (gitignored, 32 raw bytes). **Back it up alongside the certificate.**
- **The check** runs 20 seconds after launch and then daily (`NSBackgroundActivityScheduler`),
  never while recording or uploading. Settings → Updates has Check Now, the notes, Install and
  Relaunch, and Skip This Version. One notification per new version. When a newer build exists but
  this copy cannot replace itself (see refusals below), the check says so up front, with the reason
  and the curl install line, instead of offering an Update button that would fail. A debug build
  under a checkout's `build/` folder skips automatic checks altogether unless the feed is
  overridden; Check Now still works there and reports why it will not install.
- **The install** (`UpdateInstaller`) streams the zip into a private temp folder while hashing it,
  unpacks with `ditto` (which keeps signatures intact), confirms the bundle ID, version and build
  match the manifest, then validates the new bundle against the running app's designated requirement
  with `SecStaticCodeCheckValidityWithErrors`. That one call proves "validly signed, unmodified, same
  identity as me". The bundle is copied next to the old one and the two are swapped atomically with
  `renamex_np(RENAME_SWAP)`. A detached shell waits for the app to exit, removes the old bundle, and
  reopens the new one. Grants survive because TCC and the Keychain key on identity, not path.
- **Refusals** are tested headlessly: tampered zip, wrong or unknown key, lower version, wrong
  bundle ID, a zip whose app is another version, another signing identity, and locations the app
  cannot replace itself in (read-only volume, Downloads, a source checkout's `build/`). In the last
  case Settings shows the curl install line instead.

To try the whole loop against a release that is not published yet:

```bash
Scripts/publish.sh 0.2.1 --local                     # dist/: zip + signed latest.json, no git changes
python3 -m http.server -d dist 8000 --bind 127.0.0.1
defaults write com.automattic.loominate updateFeedURL http://127.0.0.1:8000/latest.json
~/Applications/Loominate.app/Contents/MacOS/Loominate --check-update    # or Settings → Check Now
defaults delete com.automattic.loominate updateFeedURL                  # back to GitHub
```

`LOOMINATE_UPDATE_FEED` in the environment does the same for one process. With an override, the zip
is looked up next to the manifest instead of at the URL inside it, so a served `dist/` works as is.

## Releasing

One command does everything, and it is safe to rerun after a failure:

```bash
Scripts/publish.sh 0.2.0 [--notes-file NOTES.md]
```

Needs, once: `gh auth login`, the signing certificate, `.secrets/wpcom.env`, and the update signing
key (`Scripts/sign-manifest.sh keygen .secrets/update-signing-key`, then paste the printed line into
`UpdateConfig.swift`). The script refuses to run from anything but a clean, pushed `trunk`.

What it does: writes the version into `Scripts/Info.plist` and commits `Release vX.Y.Z` with an
annotated tag; builds a release bundle with `BUILD_NUMBER` = commit count (so builds only go up) and
`REQUIRE_SIGNING=1`; zips it with `ditto`; makes the DMG; signs `latest.json`; verifies that
manifest with the public key the app actually ships; pushes; creates the GitHub Release with the
zip, the DMG and `latest.json`, SHA-256 sums in the notes; and finally downloads `latest.json` back
from GitHub to confirm the feed serves what was signed. `--dry-run` stops before the push.

Versions are `x.y.z` and compared numerically per component; the build number only breaks ties.
Release notes come from `--notes-file`, or from the commit subjects since the previous tag.

### Changing the signing identity

Moving to a Developer ID certificate (or replacing a lost one) changes the code identity, which
invalidates every user's TCC grants once and would make the updater refuse the build. For that one
release, sign the manifest with `--allows-identity-change`: the installer then accepts a validly
signed bundle with a different identity and tells the user, after relaunch, that permissions and the
WordPress.com sign-in must be granted again. `Scripts/release.sh` holds the notarization steps for
when a Developer ID exists; it would need the same manifest signing added to its end.

### Rotating the update key

Add the new public key to `UpdateConfig.swift` (keep the old one), ship a release signed with the old
key so every installed copy learns the new key, then switch `.secrets/update-signing-key` and remove
the old key in a later release.

## Icons

`Assets/AppIcon-1024.png`, `Assets/loominate-menubar.svg` and `Assets/loominate-logo.svg` are the
sources; `Scripts/make-icons.sh` produces `AppIcon.icns`, the menu bar template images and the
README logo in light and dark variants (needs ImageMagick; SVGs are rendered by macOS itself). The
generated files are committed so only someone changing the artwork needs the tool.

## Known limitations

- Record and Stop only: no pause, trim or region selection yet.
- A captured window that is resized mid-recording scales inside the original frame.
- Apple silicon only; the build is not universal.
- Not notarized: a copy that arrives through a browser (the DMG) needs "Open Anyway" in
  System Settings the first time. The curl installer and the self-updater don't, because nothing
  they write is quarantined.
- A fresh VideoPress link plays at low quality first; the full-quality rendition follows a few minutes later.
- macOS periodically re-confirms that the app may record the screen, as it does for any app using
  ScreenCaptureKit outside Apple's own picker.
- The toolchain's Command Line Tools lack SwiftUI's `@State` macro plugin, so views use `@Observable`
  models and plain stored properties instead.
