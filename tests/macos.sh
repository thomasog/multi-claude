#!/bin/zsh
# macOS tests: argument handling, the Core Image recolor and `add` with a fake Claude.app; no Claude
# needed. Run: zsh tests/macos.sh
set -uo pipefail
repo=${0:A:h:h}
cli=$repo/src/macos/multi-claude
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
# Nothing may touch the real home or the installed Claude.
export HOME=$tmp/home TMPDIR=$tmp MULTI_CLAUDE_CLAUDE_APP=$tmp/Claude.app; unset XDG_DATA_HOME
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
  check 'the launcher stays open while the profile runs' '[[ $(/usr/libexec/PlistBuddy -c "Print :OSAAppletStayOpen" "$app/Contents/Info.plist") == true ]]'
  check 'list shows the profile'              'grep -q "^Work " <<<"$(zsh "$cli" list)"'
  check 'same name in another case is refused' 'exit_is 64 add work'
  check 'remove finds the profile in any case' 'exit_is 0 remove work && [[ ! -e $app ]]'
  # Another app that happens to be called "Claude <name>.app" is not ours: never touched.
  other="$HOME/Applications/Claude Notes.app"
  plist "$other" com.example.notes
  check 'add refuses an app that is not a profile' 'exit_is 1 add Notes && grep -qx "~/Applications/Claude Notes.app exists and is not a multi-claude profile." <<<"$(zsh "$cli" add Notes 2>&1)"'
  check 'open and remove ignore it'           'exit_is 1 open Notes && exit_is 1 remove Notes && [[ -f $other/Contents/Info.plist ]]'
  check 'list ignores it'                     'grep -q "^No profiles yet" <<<"$(zsh "$cli" list)"'
  # `open`, with stand-ins for Claude's processes and for the two commands that act on the desktop.
  mkdir -p "$tmp/stub"
  print -r -- '#!/bin/zsh
print -r -- "$@" >> "$STUB_LOG"; env | grep -E "^(CLAUDE|ANTHROPIC|MULTI_CLAUDE_LAUNCHER)" >> "$STUB_LOG"; exit ${STUB_EXIT:-0}' > "$tmp/stub/open"
  cp "$tmp/stub/open" "$tmp/stub/osascript"; chmod +x "$tmp/stub/open" "$tmp/stub/osascript"
  export STUB_LOG=$tmp/stub.log
  # As the launcher calls it: without the flag, `open` only hands over to the launcher.
  stubbed() { : > "$STUB_LOG"; MULTI_CLAUDE_LAUNCHER=1 PATH="$tmp/stub:$PATH" zsh "$cli" "$@" >/dev/null 2>&1; }
  zsh "$cli" add Run >/dev/null 2>&1
  data="$HOME/Library/Application Support/Claude-Run"
  check 'open from a terminal goes through the launcher' ': > "$STUB_LOG"; PATH="$tmp/stub:$PATH" zsh "$cli" open run >/dev/null 2>&1 && grep -qxF -- "$HOME/Applications/Claude Run.app" "$STUB_LOG"'
  check 'a launcher from before 0.1.6 still opens Claude' '/usr/libexec/PlistBuddy -c "Delete :OSAAppletStayOpen" "$HOME/Applications/Claude Run.app/Contents/Info.plist" && : > "$STUB_LOG"; PATH="$tmp/stub:$PATH" zsh "$cli" open Run >/dev/null 2>&1 && grep -qF -- "--user-data-dir=$data" "$STUB_LOG"'
  check 'open starts Claude on the profile folder' 'stubbed open Run && grep -qF -- "-n -a $MULTI_CLAUDE_CLAUDE_APP --args --user-data-dir=$data" "$STUB_LOG"'
  check 'open drops the variables of a Claude session' 'CLAUDE_CODE_USER_EMAIL=a ANTHROPIC_BASE_URL=b CLAUDECODE=1 stubbed open Run && grep -qF -- "--user-data-dir" "$STUB_LOG" && ! grep -qE "^(CLAUDE|ANTHROPIC|MULTI_CLAUDE_LAUNCHER)" "$STUB_LOG"'
  check 'the launcher sees a stopped profile'  '! zsh "$cli" _running Run'
  ( exec -a "$MULTI_CLAUDE_CLAUDE_APP/Contents/Frameworks/Claude Helper.app/Contents/MacOS/Claude Helper --type=gpu --user-data-dir=$data" sleep 30 ) & helper=$!
  check 'a helper alone is not the main process'    'stubbed open Run && grep -qF -- "--user-data-dir=$data" "$STUB_LOG"'
  ( exec -a "$MULTI_CLAUDE_CLAUDE_APP/Contents/MacOS/Claude --user-data-dir=$data" sleep 30 ) & main=$!
  check 'the launcher sees a running profile'  'zsh "$cli" _running run'
  check 'open of a running profile starts no second Claude' 'stubbed open Run && ! grep -qF -- "--user-data-dir" "$STUB_LOG"'
  check 'open of a running profile brings that process forward' 'grep -qF -- "ProcessIdentifier($main)" "$STUB_LOG"'
  check 'and reopens its window, as a Dock click does' 'grep -qF -- "0x72617070, \$.NSAppleEventDescriptor.descriptorWithProcessIdentifier($main)" "$STUB_LOG"'
  check 'open survives a process that is quitting' 'STUB_EXIT=1 stubbed open Run'
  kill $main $helper
  : > "$STUB_LOG"
  ( export MULTI_CLAUDE_LAUNCHER=1 PATH="$tmp/stub:$PATH"; exec -a "$MULTI_CLAUDE_CLAUDE_APP/Contents/MacOS/Claude --user-data-dir=$data" zsh "$cli" open Run ) >/dev/null 2>&1
  check 'open from a terminal inside the profile starts no second Claude' 'grep -qF "ProcessIdentifier(" "$STUB_LOG" && ! grep -qF -- "--user-data-dir" "$STUB_LOG"'
  ( exec -a "fake --user-data-dir=$data" zsh "$cli" list ) > "$tmp/list.out"
  check 'list sees a profile from a terminal inside it' 'grep -q "^Run  *running" "$tmp/list.out"'
  ( exec -a "$MULTI_CLAUDE_CLAUDE_APP/Contents/MacOS/Claude --user-data-dir=$data" sleep 30 ) & main=$!
  check 'a removed profile is not running for its launcher' 'exit_is 0 remove Run && ! zsh "$cli" _running Run'
  kill $main
  mkdir -p "$HOME/.local/bin"; cp "$cli" "$HOME/.local/bin/multi-claude"
  check 'uninstall removes profiles only'     'exit_is 0 add Two && exit_is 0 uninstall && [[ ! -e "$HOME/Applications/Claude Two.app" && -d $other ]]'
  check 'uninstall leaves a real ~/.local/bin/multi-claude alone' '[[ -f $HOME/.local/bin/multi-claude && ! -L $HOME/.local/bin/multi-claude ]]'
else
  print '  skip add with a fake Claude.app (needs macOS)'
fi

(( failed == 0 )) && print 'all tests passed'
exit $failed
