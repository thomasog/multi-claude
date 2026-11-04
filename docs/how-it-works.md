# How it works

## One app, one data folder per profile

Claude Desktop is an Electron app. Electron allows one running instance per **data folder** and keeps
the sign-in inside that folder. Starting the official app with `--user-data-dir=<folder>` therefore
gives a second, fully separate instance with its own login. That is all a profile is.

On macOS Claude holds no such lock, so a second start would run it twice on the same data. There
`multi-claude open` looks for the profile first and, when it runs, brings it forward by process ID.

| System  | Profile data                                  | Launcher                                                  |
|---------|-----------------------------------------------|-----------------------------------------------------------|
| Windows | `%USERPROFILE%\.multi-claude\data\Claude-<name>` | Start menu shortcut `Claude <name>`                    |
| macOS   | `~/Library/Application Support/Claude-<name>` | `~/Applications/Claude <name>.app`                        |
| Linux   | `~/.config/Claude-<name>`                     | `~/.local/share/applications/multi-claude-<name in lowercase>.desktop` |

A profile's own Claude Code folder, if it has one, is `.claude` inside its data folder.

Nothing inside Claude changes, so app updates apply to every profile.

On Windows the profile data stays out of AppData on purpose. The Store app runs in a package that
virtualizes its writes there, so a folder under `%LOCALAPPDATA%` would really sit in the package's
private copy (`%LOCALAPPDATA%\Packages\Claude_…\LocalCache`): Explorer can't see it, so Claude's own
**Edit Config** button points nowhere, and Windows deletes it when the app is reset or uninstalled.
Profiles made before 0.1.3 lived there; `open` moves each one to its new folder the next time it
starts while closed.

On Windows, Claude Desktop 2.42304 and later move the regular Claude's data out of the app package,
to `%LOCALAPPDATA%\Claude-Data\<package>`. 3.1623 and later keep a profile on the folder its
`--user-data-dir` names, so profiles simply see the real LocalAppData. 2.42304 finds that folder from
`LOCALAPPDATA` alone, so there a profile started plainly would open the regular Claude's folder
instead of its own (and, with the regular Claude open, just hand over to it). On 2.42304, once that
move has happened, `open` starts the profile with `LOCALAPPDATA` pointing at a view of the real
folder, `%USERPROFILE%\.multi-claude\local`: one junction per folder of the real LocalAppData,
except Claude's own (`Claude`, `Claude-*`, `Claude Nest`, `AnthropicClaude`) and, under `Packages`,
Claude's package. Claude finds no `Claude-Data` there and keeps the profile's own folder, while
everything the profile starts (MCP servers, Claude Code sessions, terminals) still finds its usual
folders, such as the npm cache, through the junctions. A tool that creates a brand-new folder
directly in LocalAppData while a profile runs creates it in the view. In the view's copy of Claude's
package the profile keeps its own Claude in Chrome host; the watcher points the browsers back at the
regular Claude, as for any profile, and puts Claude's "Open with" entry, which the profile writes
with the alias it sees, back on the real one. `uninstall` removes the view's junctions, never what
they point to.

0.1.1 to 0.1.3 used a `\\?\C:\...` spelling of `LOCALAPPDATA` instead, which Claude treats as a share.
npm can't work with that spelling, so MCP servers started through `npx` failed in profiles.

The watcher also checks which folder Claude's helper processes really use, and leaves the windows on
the regular Claude button if it is not the profile's own.

## Colored icons

`add` takes the Claude icon already installed on the computer and recolors it, so no artwork ships
with this project.

All three systems use the same algorithm: every colored pixel takes the target hue, saturation and
brightness are scaled so the logo's brand color lands exactly on the target, and the white glyph
stays white.

- **Windows** does it in C# (`System.Drawing`, compiled in memory) and writes a multi-size `.ico`.
- **Linux** does it with a small standard-library Python PNG reader and writer.
- **macOS** does it in JavaScript for Automation, built into the system, then builds the `.icns` with
  `sips` and `iconutil`.

## Its own taskbar button (Windows)

Windows groups taskbar buttons by **AppUserModelID**, and every Claude window declares the same one,
so a second profile would otherwise stack onto the regular Claude button. A profile's Start menu
shortcut carries the ID `MultiClaude.<name>` and runs `multi-claude open <name>`, which:

1. starts Claude with the profile's data folder (if the profile is already open, Claude focuses it);
2. keeps running, hidden, and gives the profile's windows the same ID and relaunch properties, so
   the window and its pinned button become one colored button;
3. exits when the profile closes. Each profile has at most one watcher.

If tagging ever fails, the window simply appears under the regular Claude button.

## Its colored icon in the Dock (macOS)

The running profile is Claude itself, so its Dock icon is always Claude's. The profile's launcher is
therefore a stay-open applet: it opens the profile, then stays in the Dock with its colored icon
marked as running until the profile quits (it checks every 3 seconds, and quits after a minute if
the profile never starts). Clicking it brings the profile forward as a Dock click on the profile
would: it activates the process and sends it a reopen event, which brings back a closed window.
`multi-claude open` from a terminal goes through the launcher too.

## Sign-in

A browser sign-in returns through a `claude://` link, and the system gives that link to whichever
Claude is open, usually the regular one. An e-mail sign-in can avoid the link: open the e-mail's link
in the browser, do not let it open Claude, and ask for a code to type in the profile. That works with
every Claude open. With single sign-on, quit every other Claude first, including other profiles
(on Windows, also from the tray). After that, each profile keeps its own login.

## Claude Code

The Code tab runs Claude Code, which keeps its settings, account state (`.claude.json`), sessions
and memory in one folder, `~/.claude` unless `CLAUDE_CONFIG_DIR` names another one. Claude Desktop
follows the same variable for the files it writes there. With every profile on `~/.claude`, two
accounts overwrite each other's account record and caches, and their transcripts and project memory
end up in one `projects` folder. So each profile picks one of three modes, with
`multi-claude add <name> --claude-code <mode>`:

| Mode     | The profile's Code tab uses                                                         |
|----------|-------------------------------------------------------------------------------------|
| `own`    | `.claude` in the profile's data folder: its own settings, sessions and memory       |
| `synced` | the same, with `skills`, `agents`, `commands` and `output-styles` linked to `~/.claude`, a `CLAUDE.md` that imports `~/.claude/CLAUDE.md`, and a one-time copy of `~/.claude/settings.json` |
| `shared` | `~/.claude` itself, as every profile did before                                     |

- **The folder is the setting.** A profile with `.claude` in its data folder is `own` or `synced`
  (`synced` while it holds one of multi-claude's links or its `CLAUDE.md` import); without one it is
  `shared`. `open` starts Claude with `CLAUDE_CONFIG_DIR` pointing there, so Claude and Claude Code
  agree (on macOS through `open --env`). Nothing else records the choice, so it survives `remove` and `uninstall` and goes when
  the data folder is deleted.
- **Defaults.** A new profile, one without a data folder yet, gets `own`. A profile that already
  has data keeps its mode when `add` runs again without `--claude-code`, so existing profiles stay
  `shared` until you change them. `--claude-code` alone changes only the mode: the icon and color
  stay.
- **Links, not copies.** `skills`, `agents`, `commands` and `output-styles` are symbolic links
  (junctions on Windows, which need no Developer Mode), so a skill added in either place is there in
  both. `add` makes a link only where the profile has nothing of that name and `~/.claude` has the
  folder; what the profile has itself always wins, and nothing is ever created in `~/.claude`.
  `CLAUDE.md` is a one-line `@~/.claude/CLAUDE.md` import, Claude Code's own way to include a file.
- **settings.json is copied once**, when the profile has none: a link would need Developer Mode on
  Windows. After that the copy is the profile's own and is never refreshed. It is not copied at all
  if it has an `env` block or a credential helper (`apiKeyHelper` and the like), which can hold keys
  and tokens. Plugins named in it are not installed in the profile.
- **Never copied or linked:** `.credentials.json`, `.claude.json` (the account record, user-scope MCP
  servers), sessions of other profiles, plugins, caches.
- **Switching** keeps everything. `shared` renames the profile's folder to `.claude.off`; `own` or
  `synced` renames it back. Moving to `own` or `synced` from `shared` also copies the profile's own
  sessions from `~/.claude`: Claude Desktop lists each Code session with its `cliSessionId`, which
  names the transcript, so multi-claude copies exactly those transcripts, their session folders and
  their file history, never overwriting and never changing `~/.claude`. Only those move: project
  memory (`projects/<dir>/memory`, which every account on `~/.claude` wrote to), plans and the rest
  stay in `~/.claude`. If the copy stops halfway the profile stays `shared`, and running `add` again
  goes on from there. Nothing is copied back to `~/.claude`: sessions from an own period come back
  with the folder. A change to or from `shared` needs the profile closed; on Windows, a profile made
  before 0.1.3 must open once first, so its data moves out of AppData.
- **Don't set `CLAUDE_CONFIG_DIR` yourself** in a profile's "Environment variables" (Code tab, Edit
  local environment). Claude Code would follow it, but Claude Desktop's own writes would not, which
  splits the account record across two folders. A `CLAUDE_CONFIG_DIR` in your own environment is
  removed when a profile starts, as are all `CLAUDE*` and `ANTHROPIC*` variables; `doctor` mentions
  it.

To use a profile's Claude Code in a terminal, run `multi-claude code Work`. It starts `claude` from
the PATH on Work's own folder, as `open` does for the Code tab: it drops inherited `CLAUDE*` and
`ANTHROPIC*` variables and sets `CLAUDE_CONFIG_DIR`. Everything after the name goes to `claude`
untouched (`multi-claude code Work --resume`, `multi-claude code Work -p "..."`), and `claude`'s exit
code is multi-claude's. A `shared` profile runs on `~/.claude` and says so on stderr. It needs no
running Claude Desktop, and it never touches sign-ins: that terminal signs in on its own, the first
time. Quit those terminals too before changing the profile's Claude Code mode. On Windows
PowerShell 5.1, an empty argument or one with a `"` inside can reach `claude` changed. Other tools
can still use the folder by setting `CLAUDE_CONFIG_DIR` themselves.

## What profiles share

Each profile has its own account, conversations, list of Claude Code sessions, scheduled tasks, MCP
configuration and app settings, and, unless its Claude Code mode is `shared`, its own Claude Code
folder. They share what exists once per user: global keyboard shortcuts, the browser's entry for
Claude in Chrome, on Windows the packaged app's startup entry, and `~/.claude` for profiles whose
Claude Code is `shared`. The README lists how to keep your regular Claude in charge of these.

Browsers find Claude through one native-messaging entry per user
(`com.anthropic.claude_browser_extension`): a registry key on Windows, a JSON manifest in each
browser's `NativeMessagingHosts` folder on macOS and Linux. The entry only names the helper the
browser starts. That helper reaches Claude through one socket or pipe per user, and Claude in Chrome
works with the account it was paired with, not with whichever Claude wrote the entry (as read in
Claude Desktop 4.16336). On macOS and Linux every Claude names the same helper inside Claude's own
install, so there is nothing to keep. On Windows the packaged app registers it inside its package's
redirected AppData folder, but a profile can register a copy in its own data folder, which would
leave the browser pointing at nothing once that folder is deleted. So on Windows, profile launchers
run `multi-claude open`, which starts a small watcher for as long as the profile is open; whenever a
profile has taken the entry, the watcher points it back to the regular Claude's own manifest, in
Chrome, Edge, Brave and Chromium. It never touches the entry if the regular Claude has not paired.

## Installation

The install commands download a versioned release archive. The release workflow writes that version
and the archive's SHA-256 into the installer itself, so the installer only accepts the exact archive
it was published with, and the release carries a build provenance attestation. Everything installs
in your user folder (on Windows the command is also added to your user PATH; on macOS and Linux it
is linked into `~/.local/bin`); nothing needs admin rights.

Plain scripts were chosen over a compiled installer: an unsigned executable triggers SmartScreen and
antivirus heuristics, and every new build starts with no reputation. Scripts can be read before they
run.
