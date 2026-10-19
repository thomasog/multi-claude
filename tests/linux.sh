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
export XDG_DATA_HOME=$tmp/data XDG_CONFIG_HOME=$tmp/config
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
check 'invalid color exits 64'                'exit_is 64 add Work --color banana'
check 'missing color exits 64'                'exit_is 64 add Work --color'
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

check 'uninstall cleans up'                   'exit_is 0 add Two && exit_is 0 uninstall && [ ! -d "$XDG_DATA_HOME/multi-claude" ] && ! ls "$XDG_DATA_HOME/applications" | grep -q multi-claude'
if [ $failed -eq 0 ]; then echo 'all tests passed'; fi
exit $failed
