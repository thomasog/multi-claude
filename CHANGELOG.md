# Changelog

All notable changes are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project uses
[Semantic Versioning](https://semver.org/).

## [Unreleased]

## [0.1.1] - 2026-10-19

### Fixed

- Windows: profiles open again with Claude Desktop 2.42304 and later. That version moves the regular
  Claude's data out of the app package and sent every profile to that folder, so a profile either
  did not open (the regular Claude was running) or opened the regular account.
- Windows: Claude in Chrome pairing repair finds the regular Claude's manifest in its new
  `Claude-NativeHost` folder.

### Changed

- Windows: the watcher only gives windows a profile's taskbar button after checking that Claude
  really runs on that profile's folder, and logs to `open.log` when a profile closes without opening.
- `Data` is a reserved profile name on every system, like `3p`: Claude uses `Claude-Data` itself.
- `doctor` on Windows shows where the regular Claude keeps its data.

## [0.1.0] - 2026-10-13

### Added

- `multi-claude add | list | open | remove | doctor | uninstall` on Windows, macOS (beta) and Linux
  (experimental).
- Profiles: the official Claude Desktop with its own `--user-data-dir`, so each keeps its own sign-in.
- Icons recolored from the installed Claude logo, in seven named colors or any hex value.
- Windows: each profile gets its own taskbar button through AppUserModelID tagging.
- Claude in Chrome stays paired with the regular Claude (Chrome, Edge, Brave, Chromium) while
  profiles run; `doctor` shows the pairing per browser.
- Installers that download a versioned release and verify it against the SHA-256 written into them,
  with build provenance attestations, and offer to add a profile with a color picker.

[Unreleased]: https://github.com/thomasog/multi-claude/compare/v0.1.1...HEAD
[0.1.1]: https://github.com/thomasog/multi-claude/compare/v0.1.0...v0.1.1
[0.1.0]: https://github.com/thomasog/multi-claude/releases/tag/v0.1.0
