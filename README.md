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
  one track. The default screen recorder on a Mac can't do that, and it's the main reason Loominate exists.
- Adds an optional camera bubble. Drag it to a corner, even mid-recording, and that's where it lands in the video.
- Keeps files small. A five-minute walkthrough is usually tens of megabytes.
- Uploads to VideoPress and copies the link, so the video plays in any browser with nothing to install.
- Leaves every recording on your Mac until you decide to upload it. Botched take? Discard it and go again.
- Talks to WordPress.com to upload, and to GitHub once a day to look for a new version. No
  analytics, nothing else.

## Install

Paste this into Terminal and press Return:

```sh
curl -fsSL https://raw.githubusercontent.com/a8cteam51/loominate/trunk/install.sh | sh
```

It fetches the latest release, checks it, puts Loominate in your Applications folder and opens it.
Run the same line again later to upgrade, or let the app do it: Loominate checks for new versions
once a day and installs them with one click.

If you'd rather download something, grab `Loominate-<version>.dmg` from
[Releases](../../releases) and drag Loominate into Applications. Loominate isn't notarized with
Apple yet, so macOS refuses to open a copy that arrived through a browser until you allow it under
System Settings → Privacy & Security ("Open Anyway"). The Terminal line above skips that dance.

Either way, allow Screen Recording when macOS asks, reopen the app, and sign in with your
WordPress.com account. You'll need a Mac with Apple silicon running macOS 26 or later, and a
WordPress site with VideoPress: a WordPress.com site on a plan that includes it, or a
Jetpack-connected site with the VideoPress plan. After you sign in, Loominate lists the sites
that qualify.

## Using it

Click the Loominate icon in the menu bar, pick a screen or a window, and decide whether you want
the camera, the mic and system audio. Press Start Recording. After a short countdown you're live,
and you can stop from the floating control or the menu bar.

When you stop, a small panel asks what to do with the recording: upload it and copy the link, keep
the file, or discard it. You can type a title while the upload runs. There's also a title prefix in
Settings, which is handy when a whole team shares one site.

If you belong to more than one site with VideoPress, choose where uploads go under Settings →
WordPress.com account. Share links play for anyone who has them, unless the site restricts its
VideoPress videos to members.

## Privacy

Loominate asks macOS for permission to see your screen and devices, and asks you once, in your
browser, to let it upload to WordPress.com. The sign-in is stored in the macOS Keychain. No
recording leaves your Mac until you press Upload, and nothing about how you use the app is
collected. Once a day the app downloads a small signed file from GitHub to find out whether a
newer version exists; you can turn that off under Settings → Updates.

## For developers

Loominate is written in Swift with Apple frameworks only; there are no third-party dependencies.
[docs/DEVELOPMENT.md](docs/DEVELOPMENT.md) covers building it, the headless test modes, how
updates are signed, and shipping a release. [CONTRIBUTING.md](CONTRIBUTING.md) has the short
version of how to send changes.

## License

[GPL-2.0-or-later](LICENSE). Made by WordPress.com Special Projects at Automattic.
