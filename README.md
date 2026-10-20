<div align="center">

# multi-claude

**Run multiple Claude Desktop accounts at once.**<br>
Work and personal profiles, each with its own sign-in, its own colored icon and its own taskbar
button. Like browser profiles, for Claude.

[![CI](https://github.com/thomasog/multi-claude/actions/workflows/ci.yml/badge.svg)](https://github.com/thomasog/multi-claude/actions/workflows/ci.yml)
[![Release](https://img.shields.io/github/v/release/thomasog/multi-claude)](https://github.com/thomasog/multi-claude/releases/latest)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue)](LICENSE)
<br>
![Windows: supported](https://img.shields.io/badge/Windows-supported-0078D4)
![macOS: beta](https://img.shields.io/badge/macOS-beta-555555)
![Linux: experimental](https://img.shields.io/badge/Linux-experimental-E95420)

</div>

<p align="center">
  <img src="assets/taskbar.png" width="278" alt="Windows taskbar with three Claude buttons: the regular orange Claude, a blue Work profile and a green Personal profile">
  <br><sub>The regular Claude, a Work profile and a Personal profile, each with its own taskbar button.</sub>
</p>

Claude Desktop signs in to one account at a time. multi-claude adds **profiles**: each profile is the
official app opened with its own data folder, so it keeps its own login. Open them side by side, pin
them next to each other, tell them apart by color.

- **The official app, untouched.** Nothing is patched or copied, so Claude's updates keep working.
- **No artwork shipped.** Each icon is recolored from the Claude logo already on your computer.
- **Its own taskbar button on Windows**, instead of one more window stacked on the regular Claude.
- **Small and readable.** Plain scripts, no dependencies, no admin rights.

## Requirements

- **Windows 10 or 11** with Claude Desktop from [claude.ai/download](https://claude.ai/download).
- **macOS** with Claude in `/Applications`.
- **Linux** with the official Claude Desktop package for Ubuntu or Debian, and `python3`.

## Install

**Windows**, in PowerShell:

```powershell
irm https://github.com/thomasog/multi-claude/releases/latest/download/install.ps1 | iex
```

**macOS and Linux**, in a terminal:

```sh
curl -fsSL https://github.com/thomasog/multi-claude/releases/latest/download/install.sh | sh
```

Your regular Claude stays as it is. The installer offers to add an extra one right away: give it a
name (e.g. *Work*) and pick a color. It installs for your user only and checks the download against
the SHA-256 pinned in the installer. Every script is in this repository if you'd like to read it
first.

## Use

```sh
multi-claude add Work --color blue    # a new profile, in the Start menu, Applications or app launcher
multi-claude list                     # your profiles, with the last usage Claude recorded
multi-claude remove Work              # remove it; its sign-in data is kept
multi-claude doctor                   # check this computer
multi-claude doctor --selftest        # Windows only: also test taskbar tagging
```

Open a profile from its launcher. (`multi-claude open Work` does the same; on Windows it keeps the
terminal busy until the profile closes.)

Colors: `green` (default) `blue` `purple` `red` `teal` `pink` `gray`, or any hex value such as
`C0392B`.

> [!IMPORTANT]
> **Signing in to a new profile:** choose **Sign in with a code**, so the login stays in that window.
> With single sign-on, quit every other Claude first, including other profiles (on Windows, also from
> the tray): the browser returns the login through a `claude://` link, which goes to whichever Claude
> is open. Each profile remembers its login.

More: [how it works](docs/how-it-works.md) · [troubleshooting](docs/troubleshooting.md)

## FAQ

**Can Claude Desktop be signed in to two accounts at the same time?**
Not by itself: the app holds one sign-in. With multi-claude each account gets its own profile, so you
can have, say, your work and personal accounts open side by side, each in its own window.

**How is this different from an account switcher?**
Account switchers keep one Claude open and swap its sign-in when you pick another account, which
restarts Claude (and closes every Claude window, profiles included). multi-claude keeps every account
open at once and never touches sign-ins: each profile signs in on its own.

**Can I see how much each account has used?**
`multi-claude list` shows each profile's last 5-hour and weekly usage, and `doctor` the regular
Claude's, as Claude itself recorded them the last time that profile was open. Nothing is sent
anywhere and no sign-in is read.

**Can I use Claude Code in every profile at once?**
Yes. Each profile has its own account and its own list of sessions. All profiles share `~/.claude`:
Claude Code settings, skills, memory and session transcripts.

**Do profiles combine usage limits?**
No. Each profile is simply signed in to its own account, with that account's plan and limits.

**Will my regular Claude keep working as before?**
Yes. Its data, Start menu entry, pinned button and `claude://` links are untouched; profiles only add
their own launchers. A few things exist once per computer, though. See the limitations below.

**How do I update?**
Run the install command again. To recolor a profile, run `multi-claude add <name> --color <color>`
with the same name.

## Known limitations

Some Claude features are registered once per computer, so the profiles share them. To keep your
regular Claude in charge of them:

- **Global keyboard shortcut (Quick Entry).** Only one app can own a shortcut; whichever Claude opens
  first gets it. In each profile's settings, turn the shortcut off or give it another key.
- **Open at login.** Leave this setting alone in profiles. On Windows the packaged (MSIX) app has a
  single startup entry, so turning it off in a profile can turn it off for your regular Claude too.
- **Claude in Chrome** pairs with one Claude per computer, and every instance tries to claim it.
  multi-claude keeps it on your regular Claude, in Chrome, Edge, Brave and Chromium, while profiles
  run. `multi-claude doctor` shows the pairing.
- **Updates restart every Claude.** An idle Claude may install an app update on its own, and updating
  closes all Claude windows, including the one you are working in. Quit the profiles you are not
  using.
- **Tray icons.** Every instance shows the same Claude icon in the system tray (or menu bar), with the
  same tooltip. The taskbar buttons and launchers are the ones that tell profiles apart.
- **Notifications** from a profile show up as "Claude", and clicking one may bring up your regular
  Claude.
- **Cowork on Windows** runs in one profile at a time: Claude runs one Cowork VM per Windows user.
- **macOS Dock:** the colored icon belongs to the profile's launcher. While a profile runs, the Dock
  shows Claude's own icon, because the running app is Claude itself.

## Uninstall

```sh
multi-claude uninstall
```

Your profiles' sign-in data stays in `%USERPROFILE%\.multi-claude\data` (Windows),
`~/Library/Application Support/Claude-*` (macOS) or `~/.config/Claude-*` (Linux). Delete those
folders to sign out for good.

---

<sub>multi-claude is an independent, unofficial project, not affiliated with or endorsed by Anthropic.
Claude and Anthropic are trademarks of Anthropic, PBC. [MIT License](LICENSE).</sub>
