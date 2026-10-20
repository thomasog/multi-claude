# AGENTS.md

Guidance for coding agents working on this repository. Humans: see [CONTRIBUTING.md](CONTRIBUTING.md).

## What this is

multi-claude runs several Claude Desktop accounts side by side. A profile is the official app started
with its own `--user-data-dir`; icons are recolored from the installed logo; on Windows a hidden
watcher tags the profile's windows with AppUserModelID `MultiClaude.<name>`. Read
[docs/how-it-works.md](docs/how-it-works.md) before changing behavior.

## Scope

One job: several Claude Desktop accounts open side by side, each telling itself apart, working
every time and putting nothing of the user at risk. Weigh every change against that.

- **In scope:** what makes profiles open, stay apart and be told apart: launching, separate data,
  icons and colors, the taskbar button, keeping Claude in Chrome on the regular Claude, install and
  uninstall, and fixes when Claude changes.
- **Out of scope:** what Claude already does itself or what serves another purpose: usage meters,
  account switching, syncing chats or settings between profiles, tray apps, auto-updaters.
- **Never:** read or copy sign-ins or tokens, call Anthropic's services, patch or copy the app, kill
  Claude processes we didn't start, or touch the regular Claude's data.
- **Priorities:** works correctly, then safe for the user, then stable, then fast. Prefer removing
  code to adding it. Workarounds for one Claude version live in one marked block and go once that
  version is gone.

## Commands

```sh
powershell -ExecutionPolicy Bypass -File tests\windows.tests.ps1   # Windows tests
zsh tests/macos.sh                                                 # macOS tests
python3 -m unittest discover -s tests                              # recolor unit tests
bash tests/linux.sh                                                # Linux end-to-end tests
ruff check .                                                       # Python lint
shellcheck install.sh src/linux/multi-claude tests/linux.sh
```

## Rules

- The three CLIs (`src/windows`, `src/macos`, `src/linux`) expose the same commands, options, messages
  and exit codes (`0` ok, `1` failure, `64` bad usage, and on Windows `3` for a terminal inside an app
  package). Change them together.
- No runtime dependencies: PowerShell 5.1 + C# 5 on Windows, zsh and built-in tools on macOS, bash and
  `python3` (standard library) on Linux.
- Never commit Claude artwork, icons generated from it, or anything identifying a user.
- `install.ps1` and `install.sh` must keep their `__VERSION__` and `__SHA256__` placeholders; the
  release workflow fills them in.
- Keep the README short. Details belong in `docs/`.
