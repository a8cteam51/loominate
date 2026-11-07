# Contributing to Loominate

Thanks for looking. Loominate is a small Mac app maintained by WordPress.com Special Projects at
Automattic; outside fixes and ideas are welcome.

## Before you start

- Open an issue first for anything bigger than a bug fix, so we can agree on the shape of it.
- You need a Mac with Apple silicon, macOS 26 or later and the Swift 6.4 Command Line Tools. Xcode is
  not required. [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md) covers the build, the dev signing
  certificate and the headless test commands.
- To test uploads from a source build you need your own WordPress.com OAuth app; the steps are in the
  same document.

## Ground rules

- Apple frameworks only. No third-party dependencies, no analytics, no network calls beyond
  WordPress.com and the GitHub update feed.
- Keep secrets out of the repo. `.secrets/` is gitignored for a reason; if you ever commit one, say so
  in the pull request so it can be rotated.
- Match the code around you: SwiftUI views with `@Observable` models, Swift 5 language mode, short
  comments that say why rather than what.
- Run the relevant headless commands before opening a pull request (`--record`, `--probe`, and
  `--upload` or `--check-update` if you touched those paths) and say in the description what you ran.
- Releases are cut by maintainers with `Scripts/publish.sh`; please don't bump the version in a
  pull request.

## License

By contributing you agree that your work is released under the
[GPL-2.0-or-later](LICENSE), like the rest of the project.
