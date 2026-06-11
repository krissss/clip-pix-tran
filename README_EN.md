# ClipPixTran

[简体中文](README.md)

[![CI](https://github.com/krissss/clip-pix-tran/actions/workflows/ci.yml/badge.svg)](https://github.com/krissss/clip-pix-tran/actions/workflows/ci.yml)
[![Release](https://github.com/krissss/clip-pix-tran/actions/workflows/release.yml/badge.svg)](https://github.com/krissss/clip-pix-tran/actions/workflows/release.yml)

ClipPixTran is a macOS productivity app built around three everyday workflows: Clip, Pix, and Tran. It brings clipboard, capture, and translation tools into one lightweight control panel.

## Features

- Clip: manage clipboard history so frequently used text is easy to find and reuse.
- Pix: capture, annotate, pin, and record screen content with less friction.
- Tran: translate selected text or manually entered text while reading and writing across languages.

## Installation

Install with Homebrew:

```bash
brew install --cask krissss/tap/clip-pix-tran
```

You can also download the latest ZIP or DMG from [Releases](https://github.com/krissss/clip-pix-tran/releases), then move `ClipPixTran.app` to `/Applications`.

If macOS reports that the app is from an unidentified developer, says it is damaged, or blocks launch, first make sure the download source is trusted, then clear extended attributes:

```bash
xattr -cr /Applications/ClipPixTran.app
```

## Permissions

ClipPixTran keeps core workflows local to your Mac. Depending on the features you enable, macOS may request:

- Accessibility: used for selected text and screenshot positioning.
- Screen Recording: used for screenshots, screen recording, and region capture.
- Input Monitoring: used for some global shortcuts.

Translation services may access the network; API keys are stored in the system Keychain.

## Development Requirements

- macOS 26.0 or newer.
- Xcode with the macOS 26 SDK.
- Swift 5.
- Swift Package Manager dependencies are resolved by Xcode, including `KeyboardShortcuts` and `Sparkle`.

You can also open `ClipPixTran.xcodeproj` directly and run the `ClipPixTran` scheme.

## Common Commands

```bash
make resolve-packages
make run-dev
make test
make package
```

Common targets:

- `make run-dev`: build and run a Debug app.
- `make test`: run tests.
- `make package`: build Release ZIP and DMG artifacts.
- `make clean`: remove build artifacts.

## Project Structure

```text
App/
  Shell/       macOS app entry, menu bar, settings, shortcuts, updates, onboarding
  Features/
    Clip/      Clipboard history and quick panel
    Pix/       Screenshots, recording, annotation, pinning, and history
    Tran/      Translation, providers, speech, quick panel, and history
  Shared/      Shared UI, services, persistence, and utilities
Tests/         Swift Testing coverage
Config/        Info.plist and signing config example
docs/          Changelog and release notes
```

## Contributing

Issues and pull requests are welcome. Before submitting code changes, please run:

```bash
make test
```

## License

This project is licensed under the MIT License. See [LICENSE](LICENSE) for details.
