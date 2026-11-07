<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="Assets/loominate-logo-dark.png">
    <img src="Assets/loominate-logo.png" width="441" alt="Loominate">
  </picture>
</p>

<p align="center"><strong>Record your screen. Share a link. Done.</strong></p>

<p align="center">
A native Mac app for quick screen recordings that go straight to VideoPress on your WordPress site.<br>
No accounts to create, no services in between, and the link is on your clipboard the moment the upload finishes.
</p>

---

## Why Loominate

Explaining something on screen should take less time than typing it out. Loominate lives in your
menu bar, records in one click, and hands you a link that anyone can open in a browser. The video
is hosted on VideoPress, the same infrastructure behind millions of WordPress sites, so it plays
everywhere, streams at the right quality, and stays under your control.

## What you get

- **Everything on screen.** Record a whole display or a single window, cursor included, at 1x or full Retina.
- **The audio people actually need.** Your microphone and the sound playing on your Mac, mixed into one clean track. Headphones included.
- **You, in the corner.** An optional camera bubble. Drag it where you want it; it snaps into place.
- **Small files.** Tuned for screen content, so a five-minute walkthrough weighs tens of megabytes, not a gigabyte.
- **One link.** Stop, click *Upload & Copy Link*, and a VideoPress link is ready to paste. Viewers need nothing but a browser.
- **Your call, every time.** Recordings stay on your Mac until you choose to upload. Outtakes go straight to the Trash.
- **Nothing in between.** No third-party services, no telemetry, no browser extension. Just your Mac and your WordPress site.

## Install

1. Download the latest `Loominate.dmg` from [Releases](../../releases).
2. Drag Loominate into Applications and open it.
3. Allow Screen Recording when macOS asks, reopen the app, and sign in with your WordPress.com account.

Requires macOS 26 or later and a WordPress site with VideoPress.

## Recording in twenty seconds

1. Click the Loominate icon in the menu bar.
2. Choose a screen or a window. Turn the camera, microphone and system audio on or off.
3. Press **Start Recording**. After a short countdown you're live; stop from the floating control or the menu bar.
4. Choose **Upload & Copy Link**, or keep the file, or discard it.

A few touches worth knowing: type a title while the upload runs and it's applied when it finishes;
set a title prefix in Settings to keep your team's videos easy to find; and the self-view you see
while recording is exactly where the bubble lands in the video.

## Privacy

Loominate talks to two places: your Mac's screen and devices, which macOS asks you to approve, and
WordPress.com, which you authorize once in your browser. Your sign-in lives in the macOS Keychain.
Nothing is uploaded until you say so, and nothing is collected about how you use the app.

## For developers

Loominate is written in Swift with Apple frameworks only and no third-party dependencies.
See [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md) to build it, run the headless test modes, or ship a release.

## License

[GPL-2.0-or-later](LICENSE). Made by Team 51 at Automattic.
