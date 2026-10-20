# Troubleshooting

Start with `multi-claude doctor` (on Windows, `multi-claude doctor --selftest`).

**`multi-claude: command not found` right after installing.**
On Windows, open a new terminal: the PATH change applies to new windows. On macOS and Linux, add
`~/.local/bin` to your PATH (for example, `export PATH="$HOME/.local/bin:$PATH"` in `~/.zshrc` or
`~/.bashrc`).

**A profile signed in to the wrong account.**
The browser sent the `claude://` sign-in link to the other Claude. In the profile, sign out and sign in
again with **Sign in with a code**. With single sign-on, quit every other Claude first, including other
profiles (on Windows, also from the tray).

**Claude in Chrome talks to the wrong account.**
The browser pairs with the Claude that registered last. Opening a profile through its multi-claude
launcher points it back to your regular Claude; `multi-claude doctor` shows the current pairing. If
a profile was opened some other way, open it again from its launcher, or toggle Claude in Chrome off
and on in your regular Claude.

**A keyboard shortcut opens a profile instead of the regular Claude.**
Only one app can own a global shortcut. In the profile's settings, turn its shortcut off or change it.

**Windows: "this one runs inside an app package".**
The terminal was started by a packaged app, where Windows redirects file writes, so shortcuts would
land where the Start menu can't see them. Open PowerShell from the Start menu and run the command
there.

**Windows: Edit Config (Settings > Developer) says the folder isn't there, or does nothing.**
The profile was made before 0.1.3, when its data sat in the Store app's private copy of AppData,
which Explorer can't see. Update multi-claude, quit the profile (also from the tray) and open it from
its shortcut: its data moves to `%USERPROFILE%\.multi-claude\data\Claude-<name>`, and the button works.
`%USERPROFILE%\.multi-claude\profiles\<name>\open.log` says whether the move happened.

**Windows: `Join-Path $env:LOCALAPPDATA ...` fails in a profile's terminal.**
Profiles see `LOCALAPPDATA` as a `\\?\C:\...` path (see [How it works](how-it-works.md)), which
PowerShell's `Join-Path` rejects. Use `"$env:LOCALAPPDATA\..."` or
`[Environment]::GetFolderPath('LocalApplicationData')` instead. `multi-claude` itself handles it.

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

**macOS: the launcher shows a generic icon.**
Run `multi-claude add <name> --color <color>` again to rebuild it, then remove it from the Dock and
add it again.

**Linux: Claude Desktop was not found.**
multi-claude looks for the official desktop entry named `Claude` or `Claude Desktop`.
`multi-claude doctor` shows what it found.

**Claude closed by itself while a profile was open.**
An idle Claude can install an app update, and updating closes every Claude window. Quit the profiles
you are not using.

**Sign a profile out for good.**
Run `multi-claude remove <name>`, then delete the data folder it prints.
