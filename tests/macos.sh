#!/bin/zsh
# macOS tests: argument handling, the Core Image recolor and `add` with a fake Claude.app; no Claude
# needed. Run: zsh tests/macos.sh
set -uo pipefail
repo=${0:A:h:h}
cli=$repo/src/macos/multi-claude
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
# Nothing may touch the real home or the installed Claude.
export HOME=$tmp/home MULTI_CLAUDE_CLAUDE_APP=$tmp/Claude.app; unset XDG_DATA_HOME
mkdir -p "$HOME"
failed=0
check()   { if eval "$2"; then print "  ok   $1"; else print "  FAIL $1"; failed=1; fi; }
exit_is() { zsh "$cli" "${@:2}" >/dev/null 2>&1; [[ $? -eq $1 ]]; }

print macos
check 'script parses'                       'zsh -n "$cli"'
check 'help exits 0'                        'exit_is 0 help'
check 'commands ignore case'                'exit_is 0 HELP'
check 'version works in any position'       'exit_is 0 add -v'
check 'unknown command exits 64'            'exit_is 64 frobnicate'
check 'unknown option exits 64'             'exit_is 64 add Work --bogus'
check 'invalid name exits 64'               'exit_is 64 add "a b"'
check 'reserved name exits 64'              'exit_is 64 add 3p'
check 'Claude-Data name is reserved'        'exit_is 64 add data'
check 'Windows device names are reserved'   'exit_is 64 add nul && exit_is 64 add COM1 && exit_is 64 open lpt9'
check 'device names get their own message'  'grep -qx "The name '"'Con'"' is reserved by Windows." <<<"$(zsh "$cli" add Con 2>&1)"'
check 'invalid color exits 64'              'exit_is 64 add Work --color banana'
check 'empty color exits 64'                'exit_is 64 add Work --color "" && grep -q "^Unknown color '"''"'\." <<<"$(zsh "$cli" add Work --color "" 2>&1)"'
check 'missing color exits 64'              'exit_is 64 add Work --color'
check 'doctor --selftest exits 0'           'grep -q "^Self-test: Windows only" <<<"$(zsh "$cli" doctor --selftest)"'
check 'extra argument exits 64'             'exit_is 64 add Work extra'
check 'removing an unknown profile exits 1' 'exit_is 1 remove NoSuchProfile'
check 'opening an unknown profile exits 1'  'exit_is 1 open NoSuchProfile'

# Recolor a synthetic orange PNG and check that the background lands near the target hue.
python3 -c "import sys; sys.path.insert(0, sys.argv[1]); import recolor; \
recolor.write_png(sys.argv[2], 32, 32, [[(217, 119, 87, 255)] * 32 for _ in range(32)])" \
  "$repo/src/linux" "$tmp/source.png"
check 'recolor.js writes a PNG' 'osascript -l JavaScript "$repo/src/macos/recolor.js" "$tmp/source.png" "$tmp/out.png" 1F4E8C && [[ -s $tmp/out.png ]]'
check 'recolor reaches the target hue' 'python3 - "$repo/src/linux" "$tmp/out.png" <<"PY"
import colorsys, sys
sys.path.insert(0, sys.argv[1])
import recolor
r, g, b, _ = recolor.read_png(sys.argv[2])[2][16][16]
hue = colorsys.rgb_to_hsv(r / 255, g / 255, b / 255)[0] * 360
print(f"       background hue {hue:.0f}, target 214")
sys.exit(0 if abs(hue - 214) < 25 else 1)
PY'
# Claude's own usage history: the newest sample, the windows we know, nothing for a bad file.
usage_dir="$tmp/usage"; mkdir -p "$usage_dir"
print -r -- "{\"version\":2,\"samples\":[{\"t\":1,\"u\":{\"fh\":90}},{\"t\":$(( $(date +%s) * 1000 )),\"u\":{\"fh\":34,\"sd\":12,\"oa\":0}}]}" > "$usage_dir/plan-usage-history.json"
check 'usage.js reads the newest sample'    '[[ $(osascript -l JavaScript "$repo/src/macos/usage.js" "$usage_dir") == "5h 34%, week 12% at "[0-9][0-9]:[0-9][0-9] ]]'
check 'usage.js prints nothing for a bad file' 'print -r -- "not json" > "$usage_dir/plan-usage-history.json"; [[ -z $(osascript -l JavaScript "$repo/src/macos/usage.js" "$usage_dir") ]]'
check 'usage.js prints nothing without a file' '[[ -z $(osascript -l JavaScript "$repo/src/macos/usage.js" "$tmp/no-such-folder") ]]'
# A fake Claude.app with a real .icns, so `add` builds a launcher. macOS tools only.
if command -v iconutil >/dev/null && [[ -x /usr/libexec/PlistBuddy ]]; then
  mkdir -p "$tmp/claude.iconset" "$MULTI_CLAUDE_CLAUDE_APP/Contents/Resources"
  for s in 16 32 128 256 512; do
    sips -z $s $s "$tmp/source.png" --out "$tmp/claude.iconset/icon_${s}x${s}.png" >/dev/null
    sips -z $((s * 2)) $((s * 2)) "$tmp/source.png" --out "$tmp/claude.iconset/icon_${s}x${s}@2x.png" >/dev/null
  done
  iconutil -c icns "$tmp/claude.iconset" -o "$MULTI_CLAUDE_CLAUDE_APP/Contents/Resources/electron.icns"
  plist() {   # a minimal Info.plist with the given bundle ID
    mkdir -p "$1/Contents"
    printf '<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0"><dict>%s%s</dict></plist>
'       "<key>CFBundleIdentifier</key><string>$2</string>" "<key>CFBundleIconFile</key><string>electron</string>"       > "$1/Contents/Info.plist"
  }
  plist "$MULTI_CLAUDE_CLAUDE_APP" com.anthropic.claudefordesktop
  app="$HOME/Applications/Claude Work.app"
  # On failure, show what add printed: this is the only place the whole macOS add path runs.
  check 'add builds the launcher'             'out=$(zsh "$cli" add Work --color blue 2>&1) || { print -r -- "$out"; false; } && [[ -d $app ]]'
  check 'the launcher has our bundle ID'      '[[ $(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$app/Contents/Info.plist") == io.github.thomasog.multi-claude.Work ]]'
  check 'the launcher has the colored icon'   '[[ -s $app/Contents/Resources/applet.icns ]]'
  check 'list shows the profile'              'grep -q "^Work " <<<"$(zsh "$cli" list)"'
  mkdir -p "$HOME/Library/Application Support/Claude-Work"
  print -r -- "{\"samples\":[{\"t\":$(( $(date +%s) * 1000 )),\"u\":{\"fh\":34}}]}" > "$HOME/Library/Application Support/Claude-Work/plan-usage-history.json"
  check 'list shows the last usage'           'grep -qE "^ {25} last usage: 5h 34% at [0-9]{2}:[0-9]{2}$" <<<"$(zsh "$cli" list)"'
  check 'same name in another case is refused' 'exit_is 64 add work'
  check 'remove finds the profile in any case' 'exit_is 0 remove work && [[ ! -e $app ]]'
  # Another app that happens to be called "Claude <name>.app" is not ours: never touched.
  other="$HOME/Applications/Claude Notes.app"
  plist "$other" com.example.notes
  check 'add refuses an app that is not a profile' 'exit_is 1 add Notes && grep -qx "~/Applications/Claude Notes.app exists and is not a multi-claude profile." <<<"$(zsh "$cli" add Notes 2>&1)"'
  check 'open and remove ignore it'           'exit_is 1 open Notes && exit_is 1 remove Notes && [[ -f $other/Contents/Info.plist ]]'
  check 'list ignores it'                     'grep -q "^No profiles yet" <<<"$(zsh "$cli" list)"'
  mkdir -p "$HOME/.local/bin"; cp "$cli" "$HOME/.local/bin/multi-claude"
  check 'uninstall removes profiles only'     'exit_is 0 add Two && exit_is 0 uninstall && [[ ! -e "$HOME/Applications/Claude Two.app" && -d $other ]]'
  check 'uninstall leaves a real ~/.local/bin/multi-claude alone' '[[ -f $HOME/.local/bin/multi-claude && ! -L $HOME/.local/bin/multi-claude ]]'
else
  print '  skip add with a fake Claude.app (needs macOS)'
fi

# Claude in Chrome: a profile took the browser's pairing; it must go back to the regular Claude.
support="$HOME/Library/Application Support"
main_host="$support/Claude/ChromeNativeHost/chrome-native-host"
profile_host="$support/Claude-Work/ChromeNativeHost/chrome-native-host"
chrome="$support/Google/Chrome/NativeMessagingHosts/com.anthropic.claude_browser_extension.json"
manifest() { printf '{\n  "name": "com.anthropic.claude_browser_extension",\n  "path": "%s",\n  "type": "stdio"\n}\n' "$1"; }
mkdir -p "${main_host:h}" "${chrome:h}"; touch "$main_host"; manifest "$profile_host" > "$chrome"
check 'doctor shows a profile holding the pairing' 'grep -q "Chrome: profile Work" <<<"$(zsh "$cli" doctor)"'
check 'pairing goes back to the regular Claude'   'zsh "$cli" _repair-pairing && grep -qF "\"path\": \"$main_host\"" "$chrome"'
rm "$main_host"; manifest "$profile_host" > "$chrome"
check 'pairing is left alone if the regular Claude never paired' 'zsh "$cli" _repair-pairing && grep -qF "\"path\": \"$profile_host\"" "$chrome"'
odd_host="$tmp/Claude-Ops/home/Claude/ChromeNativeHost/chrome-native-host"   # a "Claude-" folder above the regular one
manifest "$odd_host" > "$chrome"
check 'a Claude- folder elsewhere in the path is not a profile' 'grep -q "Chrome: regular Claude" <<<"$(zsh "$cli" doctor)"'
manifest "$support/Claude-Data/ChromeNativeHost/chrome-native-host" > "$chrome"
check "Claude's own Claude-Data folder is not a profile" 'grep -q "Chrome: regular Claude" <<<"$(zsh "$cli" doctor)"'

(( failed == 0 )) && print 'all tests passed'
exit $failed
