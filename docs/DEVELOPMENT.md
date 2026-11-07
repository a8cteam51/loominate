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

### Keep permissions across rebuilds

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

### The WordPress.com client secret

Uploads use a WordPress.com OAuth app. Its secret is never in the repo: `Scripts/bundle.sh` reads
`.secrets/wpcom.env` (gitignored) or `WPCOM_CLIENT_SECRET` and writes it into the built bundle's
`Info.plist` before signing. A build without it still records, but Settings shows sign-in as
unavailable. To build from source for your own site, register an OAuth app at
developer.wordpress.com/apps (type Web, redirect URL `http://127.0.0.1:52631/callback`), set its
client ID in `WPComConfig.swift`, and put the secret in `.secrets/wpcom.env`:

```
WPCOM_CLIENT_SECRET=…
```

## How it works

```
ScreenCaptureKit (screen + system audio + mic) ─► FramePacer ─► BubbleCompositor ─► AVAssetWriter (.mov)
AVCaptureSession (camera) ──latest frame──────────┘                                          │ stop
                                        Mixdown: video passthrough, audio mixed to one AAC track ─► .mp4
                                                                                                    │
     WordPress.com OAuth token (Keychain) ─► upload token ─► resumable tus upload (10 MB chunks) ─► VideoPress
                                                                       share link ─► clipboard + notification
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

Settings live in `UserDefaults`; a plain-text session log is written to
`~/Library/Logs/Loominate/loominate.log`.

## Headless test modes

The bundle's binary doubles as a CLI, which is how the pipeline is exercised without clicking:

```bash
R=build/Loominate.app/Contents/MacOS/Loominate
$R --devices                                   # cameras, mics, permission state
$R --probe ~/Movies/Loominate/some.mp4         # tracks, codecs, bitrate
$R --record --seconds 10 --out /tmp/test.mp4   # main display, system audio + default mic
$R --record --seconds 5 --window "Safari" --fake-camera --bubble-corner topRight
$R --login                                     # browser sign-in; --no-browser prints the URL
$R --whoami
$R --upload ~/Movies/Loominate/some.mp4 --title "Example"
open build/Loominate.app --args --auto-record 5 --upload   # drives the real UI end to end
```

Recording commands run under the terminal's permissions, so the terminal app needs Screen Recording
(and Microphone) access. `--fake-camera` feeds a synthetic image to the bubble so the compositor can
be tested without camera permission.

## Releasing

`make dmg` builds `dist/Loominate-<version>.dmg`, a disk image that opens to the usual
drag-to-Applications window (`Scripts/make-dmg.sh`, which sets the window layout through Finder
scripting). A DMG signed with the dev certificate runs on the builder's Mac; for other Macs the app
must be signed with a Developer ID certificate and notarized, which `Scripts/release.sh` does once
those credentials exist (`notarytool` and `stapler` ship with the Command Line Tools).

The version is `CFBundleShortVersionString` in `Scripts/Info.plist`.

## Icons

`Assets/AppIcon-1024.png` and `Assets/loominate-menubar.svg` are the sources; `Scripts/make-icons.sh`
produces `AppIcon.icns` and the menu bar template images (needs ImageMagick). The generated files
are committed so only someone changing the artwork needs the tool.

## Known limitations

- Record and Stop only: no pause, trim or region selection yet.
- A captured window that is resized mid-recording scales inside the original frame.
- Uploads currently target one configured site (`WPComConfig.swift`); a site picker is planned.
- A fresh VideoPress link plays at low quality first; the full-quality rendition follows a few minutes later.
- macOS periodically re-confirms that the app may record the screen, as it does for any app using
  ScreenCaptureKit outside Apple's own picker.
- The toolchain's Command Line Tools lack SwiftUI's `@State` macro plugin, so views use `@Observable`
  models and plain stored properties instead.
