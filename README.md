<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="Assets/loominate-logo-dark.png">
    <img src="Assets/loominate-logo.png" width="441" alt="Loominate">
  </picture>
</p>

<p align="center"><strong>Record your screen and share a VideoPress link in seconds.</strong></p>

<p align="center">
Loominate is a small Mac app that lives in your menu bar. Hit record, show someone the thing, hit stop.<br>
A moment later the video is on VideoPress and the link is on your clipboard.
</p>

---

## Why we built it

Sometimes the quickest way to answer a question is to show your screen for thirty seconds. That
shouldn't mean a gigabyte file in your Downloads folder and a third-party service holding your
video. Loominate records what you need, keeps the file small, and puts it where your WordPress
site already lives: VideoPress.

## What it does

- Records a whole display or just one window, at 1x or full Retina.
- Captures your microphone and whatever is playing on your Mac, headphones included, mixed into
  one track. The built-in recorder can't do that, and it's the main reason Loominate exists.
- Adds an optional camera bubble. Drag it to a corner and that's where it lands in the video.
- Keeps files small. A five-minute walkthrough is usually tens of megabytes.
- Uploads to VideoPress and copies the link, so the video plays in any browser with nothing to install.
- Leaves every recording on your Mac until you decide to upload it. Botched take? Discard it and go again.
- Talks to nothing except your Mac and WordPress.com. No third-party services and no analytics.

## Install

1. Download the latest `Loominate.dmg` from [Releases](../../releases).
2. Drag Loominate into Applications and open it.
3. Allow Screen Recording when macOS asks, reopen the app, and sign in with your WordPress.com account.

You'll need macOS 26 or later and a WordPress site with VideoPress.

## Using it

Click the Loominate icon in the menu bar, pick a screen or a window, and decide whether you want
the camera, the mic and system audio. Press Start Recording. After a short countdown you're live,
and you can stop from the floating control or the menu bar.

When you stop, a small panel asks what to do with the recording: upload it and copy the link, keep
the file, or discard it. You can type a title while the upload runs. There's also a title prefix in
Settings, which is handy when a whole team shares one site.

## Privacy

Loominate asks macOS for permission to see your screen and devices, and asks you once, in your
browser, to let it upload to WordPress.com. The sign-in is stored in the macOS Keychain. Nothing
leaves your Mac until you press Upload, and nothing about how you use the app is collected.

## For developers

Loominate is written in Swift with Apple frameworks only; there are no third-party dependencies.
[docs/DEVELOPMENT.md](docs/DEVELOPMENT.md) covers building it, the headless test modes, and
shipping a release.

## License

[GPL-2.0-or-later](LICENSE). Made by WordPress.com Special Projects at Automattic.
