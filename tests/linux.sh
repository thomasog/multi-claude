#!/usr/bin/env bash
# Linux end-to-end tests with a fake Claude desktop entry; no Claude needed. Run: bash tests/linux.sh
# Each check is a string run by eval: its variables are single-quoted on purpose, and the helpers
# and variables it uses look unused to ShellCheck.
# shellcheck disable=SC2016,SC2034,SC2317,SC2329
set -uo pipefail
repo=$(cd "$(dirname "$0")/.." && pwd)
cli=$repo/src/linux/multi-claude
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
# Nothing may touch the real home or the system's own Claude.
export HOME=$tmp/home XDG_DATA_HOME=$tmp/data XDG_CONFIG_HOME=$tmp/config XDG_DATA_DIRS=$tmp/system
mkdir -p "$HOME"
failed=0
check()   { if eval "$2"; then echo "  ok   $1"; else echo "  FAIL $1"; failed=1; fi; }
exit_is() { "$cli" "${@:2}" >/dev/null 2>&1; [ $? -eq "$1" ]; }

# A fake Claude: a desktop entry and a synthetic orange icon.
mkdir -p "$XDG_DATA_HOME/applications"
python3 -c "import sys; sys.path.insert(0, sys.argv[1]); import recolor; \
recolor.write_png(sys.argv[2], 32, 32, [[(217, 119, 87, 255)] * 32 for _ in range(32)])" \
  "$repo/src/linux" "$tmp/claude.png"
printf '[Desktop Entry]\nName=Claude\nExec=/usr/bin/claude-desktop %%U\nIcon=%s\n' "$tmp/claude.png" \
  > "$XDG_DATA_HOME/applications/claude-desktop.desktop"
entry=$XDG_DATA_HOME/applications/multi-claude-work.desktop

echo linux
check 'help exits 0'                          'exit_is 0 help'
check 'commands ignore case'                  'exit_is 0 HELP'
check 'version works in any position'         'exit_is 0 add -v'
check 'unknown command exits 64'              'exit_is 64 frobnicate'
check 'unknown option exits 64'               'exit_is 64 add Work --bogus'
check 'invalid name exits 64'                 'exit_is 64 add "a b"'
check 'reserved name exits 64'                'exit_is 64 add 3p'
check 'Claude-Data name is reserved'          'exit_is 64 add data'
check 'Windows device names are reserved'     'exit_is 64 add nul && exit_is 64 add COM1 && exit_is 64 open lpt9'
check 'device names get their own message'    'grep -qx "The name '"'Con'"' is reserved by Windows." <<<"$("$cli" add Con 2>&1)"'
check 'invalid color exits 64'                'exit_is 64 add Work --color banana'
check 'empty color exits 64'                  'exit_is 64 add Work --color "" && grep -q "^Unknown color '"''"'\." <<<"$("$cli" add Work --color "" 2>&1)"'
check 'missing color exits 64'                'exit_is 64 add Work --color'
check 'doctor --selftest exits 0'             'grep -q "^Self-test: Windows only" <<<"$("$cli" doctor --selftest)"'
check 'extra argument exits 64'               'exit_is 64 add Work extra'
check 'opening an unknown profile exits 1'    'exit_is 1 open Nope'
check 'add creates the desktop entry'         'exit_is 0 add Work --color blue && [ -f "$entry" ]'
check 'entry opens the profile through multi-claude' 'grep -q "^Exec=\".*/multi-claude\" open Work$" "$entry"'
check 'entry id matches its window class'     'grep -q "^StartupWMClass=multi-claude-work$" "$entry"'
check 'icon was recolored'                    '[ -f "$XDG_DATA_HOME/multi-claude/profiles/Work/icon.png" ]'
check 'same name in another case is refused'  'exit_is 64 add work'
check 'list shows the profile'                'grep -q "^Work " <<<"$("$cli" list)"'
check 'removing an unknown profile exits 1'   'exit_is 1 remove Nope'
check 'remove finds the profile in any case'  'exit_is 0 remove work && [ ! -f "$entry" ] && [ ! -d "$XDG_DATA_HOME/multi-claude/profiles/Work" ]'
printf 'not a png' > "$tmp/broken.png"
sed -i "s#^Icon=.*#Icon=$tmp/broken.png#" "$XDG_DATA_HOME/applications/claude-desktop.desktop"
check 'a failed add leaves nothing behind'    'exit_is 1 add Bad && [ ! -e "$XDG_DATA_HOME/multi-claude/profiles/Bad" ] && [ ! -f "$XDG_DATA_HOME/applications/multi-claude-bad.desktop" ] && [ -z "$(ls -A "$XDG_DATA_HOME/multi-claude/profiles")" ]'
# Claude installed system-wide (or by Flatpak/Snap): found through XDG_DATA_DIRS, icon by theme name.
mkdir -p "$XDG_DATA_DIRS/applications" "$XDG_DATA_DIRS/icons/hicolor/256x256/apps"
cp "$tmp/claude.png" "$XDG_DATA_DIRS/icons/hicolor/256x256/apps/claude-desktop.png"
printf '[Desktop Entry]
Name=Claude
Exec=/usr/bin/claude-desktop %%U
Icon=claude-desktop
'   > "$XDG_DATA_DIRS/applications/claude-desktop.desktop"
rm "$XDG_DATA_HOME/applications/claude-desktop.desktop"
check 'Claude is found in XDG_DATA_DIRS'      'grep -qF "Claude Desktop:   $XDG_DATA_DIRS/applications/claude-desktop.desktop" <<<"$("$cli" doctor)"'
check 'its themed icon is found and recolored' 'exit_is 0 add Sys && [ -f "$XDG_DATA_HOME/multi-claude/profiles/Sys/icon.png" ] && exit_is 0 remove Sys'

# Claude in Chrome: a profile took the browser's pairing; it must go back to the regular Claude.
main_host=$XDG_CONFIG_HOME/Claude/ChromeNativeHost/chrome-native-host
profile_host=$XDG_CONFIG_HOME/Claude-Work/ChromeNativeHost/chrome-native-host
chrome=$XDG_CONFIG_HOME/google-chrome/NativeMessagingHosts/com.anthropic.claude_browser_extension.json
edge=$XDG_CONFIG_HOME/microsoft-edge/NativeMessagingHosts/com.anthropic.claude_browser_extension.json
manifest() { printf '{\n  "name": "com.anthropic.claude_browser_extension",\n  "path": "%s",\n  "type": "stdio"\n}\n' "$1"; }
mkdir -p "$(dirname "$main_host")" "$(dirname "$chrome")" "$(dirname "$edge")"
touch "$main_host"
manifest "$profile_host" > "$chrome"; manifest "$profile_host" > "$edge"
check 'doctor shows a profile holding the pairing' 'grep -q "Chrome: profile Work, Edge: profile Work" <<<"$("$cli" doctor)"'
check 'pairing goes back to the regular Claude'   'exit_is 0 _repair-pairing && grep -qF "\"path\": \"$main_host\"" "$chrome" && grep -qF "\"path\": \"$main_host\"" "$edge"'
check 'doctor shows the regular Claude'           'grep -q "Chrome: regular Claude" <<<"$("$cli" doctor)"'
rm "$main_host"; manifest "$profile_host" > "$chrome"
check 'pairing is left alone if the regular Claude never paired' 'exit_is 0 _repair-pairing && grep -qF "\"path\": \"$profile_host\"" "$chrome"'
odd_host=$tmp/Claude-Ops/home/Claude/ChromeNativeHost/chrome-native-host   # a "Claude-" folder above the regular one
manifest "$odd_host" > "$chrome"
check 'a Claude- folder elsewhere in the path is not a profile' 'grep -q "Chrome: regular Claude" <<<"$("$cli" doctor)" && exit_is 0 _repair-pairing && grep -qF "\"path\": \"$odd_host\"" "$chrome"'
manifest "$XDG_CONFIG_HOME/Claude-3p/ChromeNativeHost/chrome-native-host" > "$chrome"
check "Claude's own Claude-3p folder is not a profile" 'grep -q "Chrome: regular Claude" <<<"$("$cli" doctor)"'
manifest "$XDG_CONFIG_HOME/Claude-Data/ChromeNativeHost/chrome-native-host" > "$chrome"
check "Claude's own Claude-Data folder is not a profile" 'grep -q "Chrome: regular Claude" <<<"$("$cli" doctor)"'

# ~/.local/bin/multi-claude: uninstall removes only its own link, never a real file.
bin=$HOME/.local/bin/multi-claude
mkdir -p "${bin%/*}"; cp "$cli" "$bin"
check 'uninstall cleans up'                   'exit_is 0 add Two && exit_is 0 uninstall && [ ! -d "$XDG_DATA_HOME/multi-claude" ] && ! ls "$XDG_DATA_HOME/applications" | grep -q multi-claude'
check 'uninstall leaves a real ~/.local/bin/multi-claude alone' '[ -f "$bin" ] && [ ! -L "$bin" ]'
rm -f "$bin"; mkdir -p "$XDG_DATA_HOME/multi-claude/lib"; cp "$cli" "$XDG_DATA_HOME/multi-claude/lib/multi-claude"
if ln -s "$XDG_DATA_HOME/multi-claude/lib/multi-claude" "$bin" 2>/dev/null && [ -L "$bin" ]; then
  check 'uninstall removes its own link'      'exit_is 0 uninstall && [ ! -e "$bin" ] && [ ! -L "$bin" ]'
else
  echo '  skip uninstall removes its own link (no symlinks here)'
fi
if [ $failed -eq 0 ]; then echo 'all tests passed'; fi
exit $failed
