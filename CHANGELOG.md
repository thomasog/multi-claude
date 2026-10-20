# Changelog

All notable changes are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project uses
[Semantic Versioning](https://semver.org/).

## [Unreleased]

### Changed

- Releases are published only once every file is attached, so the latest-release links never point
  at a release that is still uploading.
- macOS and Linux test-report issue templates, linked from the README, to get multi-claude tested
  on real machines.

## [0.1.5] - 2026-10-20

### Changed

- Windows: with Claude Desktop 3.1623 and later, which keeps a profile on the folder its
  `--user-data-dir` names, profiles see the real LocalAppData again. The LocalAppData view of 0.1.4
  stays only for Claude 2.42304, until that version is gone.

## [0.1.4] - 2026-10-20

### Fixed

- Windows: MCP servers started through `npx` (and other npm-based tools) work in profiles (#4).
  0.1.1 to 0.1.3 started profiles with `LOCALAPPDATA` written as `\\?\C:\...` to keep Claude
  2.42304 from opening the regular Claude's data; npm fails on that spelling ("Maximum call stack
  size exceeded"). Profiles now see a view of LocalAppData made of junctions, without Claude's own
  folders: Claude keeps the profile on its own folder, and child processes get a normal path.
- Windows: profiles no longer remove Claude's "Open with" entry for files; the watcher keeps it on the
  real launch alias.
- Windows: a profile's Claude in Chrome host stays apart from the regular Claude's, and the pairing
  repair also catches a browser pointed anywhere inside multi-claude's folder.
- Windows: `multi-claude` works from a terminal inside a profile: it finds LocalAppData through
  Windows instead of the variable.
- Windows: a release installer always installs its own verified download, even when an older
  extracted copy of multi-claude sits next to it.
- Windows: the installer installs the command even when it can't see Claude Desktop (as on macOS
  and Linux), and then skips the "add a profile" step. Some PowerShell 7 setups can't list Store
  apps, so this used to stop the install with Claude installed.
- macOS: `add` failed on launchers that `osacompile` builds without a bundle identifier; it now adds
  the key. Found by a new CI test that runs `add` against a fake `Claude.app`.
- Windows: moving a profile's data out of AppData works when the Store keeps apps on another drive
  (copy, then delete), runs once even on a double click, and never starts the profile on a missing
  folder. `list` shows a profile that still waits to move.
- Windows: the watcher no longer mistakes a new process that reused a closed Claude's ID for the
  profile, and a registry error while repairing the pairing no longer stops it.
- Device names (`CON`, `NUL`, `COM1`...) are refused as profile names.
- macOS and Linux: `uninstall` removes `~/.local/bin/multi-claude` only when it is multi-claude's own
  link (and the tests no longer touch the real home folder).
- macOS and Linux: an empty `--color` is reported as an unknown color (exit 64) instead of a shell
  error.
- macOS: `add`, `open`, `remove` and `uninstall` touch only launchers multi-claude made (by bundle
  ID), never another app called `Claude <name>.app`; the watcher lock is per user.
- Linux: Claude is also found in Flatpak and Snap installs (`XDG_DATA_DIRS`); palette PNG icons are
  recolored; a failed `add` leaves nothing behind.
- macOS and Linux: `install.sh` replaces files atomically, so a running watcher never reads a
  half-written script; the pairing repair ignores Claude's own `Claude-Data` folder.

### Changed

- `doctor --selftest` is accepted on macOS and Linux too (the self-test is Windows-only).

## [0.1.3] - 2026-10-20

### Fixed

- Windows: Edit Config in a profile's Developer settings works (#3). Profile data moves out of
  AppData, where the Store app kept it in a private copy that Explorer can't see and that Windows
  deletes when the app is reset, to `%USERPROFILE%\.multi-claude\data\Claude-<name>`. Existing
  profiles move there the next time they are opened while closed, keeping their sign-in. A Claude
  Code session whose folder was inside the profile (a scratch session) may need to be started again.
  `uninstall` leaves that data folder in place.

## [0.1.2] - 2026-10-19

### Fixed

- Windows: compile the installer and CLI helpers with the correct .NET references in PowerShell 7,
  including .NET 10 drawing dependencies, while retaining Windows PowerShell 5.1 support.
  Thanks @Yukk1No.
- Windows: `multi-claude` works from a terminal inside a profile, where `LOCALAPPDATA` is a `\\?\`
  path; the docs list that side effect for other scripts. Thanks @stavroskasidis for spotting it.

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

[Unreleased]: https://github.com/thomasog/multi-claude/compare/v0.1.5...HEAD
[0.1.5]: https://github.com/thomasog/multi-claude/compare/v0.1.4...v0.1.5
[0.1.4]: https://github.com/thomasog/multi-claude/compare/v0.1.3...v0.1.4
[0.1.3]: https://github.com/thomasog/multi-claude/compare/v0.1.2...v0.1.3
[0.1.2]: https://github.com/thomasog/multi-claude/compare/v0.1.1...v0.1.2
[0.1.1]: https://github.com/thomasog/multi-claude/compare/v0.1.0...v0.1.1
[0.1.0]: https://github.com/thomasog/multi-claude/releases/tag/v0.1.0
