# Troubleshooting

Start with `multi-claude doctor` (on Windows, `multi-claude doctor --selftest`).

**`multi-claude: command not found` right after installing.**
On Windows, open a new terminal: the PATH change applies to new windows. On macOS and Linux, add
`~/.local/bin` to your PATH (for example, `export PATH="$HOME/.local/bin:$PATH"` in `~/.zshrc` or
`~/.bashrc`).

**A profile signed in to the wrong account.**
The browser sent the `claude://` sign-in link to the other Claude. In the profile, sign out and sign in
again by e-mail: open the link in your browser, do not let it open Claude, and type the code it gives
you in the profile. With single sign-on, quit every other Claude first, including other
profiles (on Windows, also from the tray).

**Claude in Chrome talks to the wrong account.**
On Windows and Linux, the browser pairs with the Claude that registered last. Opening a profile
through its multi-claude launcher points it back to your regular Claude; `multi-claude doctor` shows
the current pairing. If a profile was opened some other way, open it again from its launcher, or
toggle Claude in Chrome off and on in your regular Claude.

**A keyboard shortcut opens a profile instead of the regular Claude.**
Only one app can own a global shortcut. In the profile's settings, turn its shortcut off or change it.

**Windows: "Claude Desktop was not found" although Claude is installed.**
You probably have the older installer's Claude, in `%LOCALAPPDATA%\AnthropicClaude`. multi-claude
works with the current app, which both the Microsoft Store and
[claude.ai/download](https://claude.ai/download) install. Install it from there.

**Windows: "this one runs inside an app package".**
The terminal was started by a packaged app, where Windows redirects file writes, so shortcuts would
land where the Start menu can't see them. Open PowerShell from the Start menu and run the command
there.

**Windows: Edit Config (Settings > Developer) says the folder isn't there, or does nothing.**
The profile was made before 0.1.3, when its data sat in the Store app's private copy of AppData,
which Explorer can't see. Update multi-claude, quit the profile (also from the tray) and open it from
its shortcut: its data moves to `%USERPROFILE%\.multi-claude\data\Claude-<name>`, and the button works.
`%USERPROFILE%\.multi-claude\profiles\<name>\open.log` says whether the move happened.

**Windows: MCP servers don't connect in a profile (npx shows `\\?\C:\...` or "Maximum call stack size exceeded").**
multi-claude 0.1.1 to 0.1.3 started profiles with `LOCALAPPDATA` written as `\\?\C:\...`, which npm
can't handle. Update multi-claude, quit the profile (also from the tray) and open it from its
shortcut. `multi-claude doctor` shows `Profiles see: LocalAppData view ...`.

**Windows: in a profile, `LOCALAPPDATA` is `%USERPROFILE%\.multi-claude\local`.**
That is the view described in [How it works](how-it-works.md), used with Claude 2.42304 only: the same
folders, reached through junctions. Updating Claude to 3.1623 or later ends it at the profile's next
start. To get the real folder in a script, use `[Environment]::GetFolderPath('LocalApplicationData')`.

**Windows: CS1069 mentioning `System.Drawing.Primitives` during installation.**
Older installers referenced only the .NET Framework drawing assembly, which fails in PowerShell 7.
Use an updated installer, or run the old installer in Windows PowerShell (`powershell.exe`). This
compiler error does not mean a security policy blocked the helper.

**Windows: "PowerShell runs in ConstrainedLanguage mode".**
Your organization restricts PowerShell (AppLocker, Device Guard or similar). multi-claude needs to
load a small helper to set icons and taskbar IDs, so ask your IT team, or use the machine's regular
Claude account only.

**Windows: a profile's window shows under the regular Claude button.**
Open the profile from its own Start menu shortcut or pinned button, not from the regular Claude. If it
still happens, `multi-claude doctor` should list its windows with `taskbar id: MultiClaude.<name>`.
The log is at `%USERPROFILE%\.multi-claude\profiles\<name>\open.log`.

**Windows: the pinned button lost its color.**
Unpin it, open the profile from the Start menu, and pin the running button again.

**macOS: the colored icon doesn't stay in the Dock while its profile runs.**
The launcher was made before 0.1.6. Run `multi-claude add <name> --color <color>` again to rebuild it.

**macOS: the launcher shows a generic icon.**
Run `multi-claude add <name> --color <color>` again to rebuild it, then remove it from the Dock and
add it again.

**Linux: Claude Desktop was not found.**
multi-claude looks for the official desktop entry named `Claude` or `Claude Desktop`.
`multi-claude doctor` shows what it found.

**Claude Code in a profile doesn't see my skills, settings or MCP servers.**
The profile has its own Claude Code folder (mode `own`, the default for new profiles). Run
`multi-claude add <name> --claude-code synced` to bring in your skills, agents, commands, output
styles and `CLAUDE.md` from `~/.claude`, and a copy of `settings.json`. `add` says if `settings.json`
was left out because it has an `env` block or a credential helper: copy what you need into the
profile's `.claude\settings.json` (macOS and Linux: `.claude/settings.json`) yourself. MCP servers
added with `claude mcp add --scope user` and plugins belong to each Claude Code folder: add them
again in the profile.

**After changing a profile's Claude Code mode, a Code session is missing from its list.**
Sessions stay in the folder they were made in. Moving to `own` or `synced` copies the profile's
sessions from `~/.claude`; sessions made while it was `own` come back when you switch back from
`shared`. Quit the profile before you change its mode.

**A profile's Claude Code still uses `~/.claude`.**
`multi-claude list` shows the profile's mode. Open the profile from its launcher, not from the
regular Claude, after quitting it (on Windows, also from the tray). If you set `CLAUDE_CONFIG_DIR` in
the profile's Code tab (Edit local environment), remove it there. On Windows,
`%USERPROFILE%\.multi-claude\profiles\<name>\open.log` names the Claude Code folder at each start.

**The first Code session in a profile asks for things again** (theme, trusting a folder).
Its own Claude Code folder starts empty; that happens once.

**Claude closed by itself while a profile was open.**
An idle Claude can install an app update, and updating closes every Claude window. Quit the profiles
you are not using. Account-switcher tools that restart Claude to swap its sign-in also close every
Claude window, profiles included. Reopen the profiles from their launchers.

**Sign a profile out for good.**
Run `multi-claude remove <name>`, then delete the data folder it prints.
