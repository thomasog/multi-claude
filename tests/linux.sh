#!/usr/bin/env bash
# Linux end-to-end tests with a fake Claude desktop entry; no Claude needed. Run: bash tests/linux.sh
# Each check is a string run by eval: its variables are single-quoted on purpose, and the helpers
# and variables it uses look unused to ShellCheck.
# shellcheck disable=SC2016,SC2034,SC2317,SC2329
set -uo pipefail
repo=$(cd "$(dirname "$0")/.." && pwd)
cli=$repo/src/linux/multi-claude
# Everything lives under a path with a space, parentheses and a plus, which a regex or a split would trip on.
base=$(mktemp -d); tmp="$base/a (x)+"; mkdir "$tmp"
trap 'rm -rf "$base"' EXIT
# Nothing may touch the real home or the system's own Claude.
export HOME=$tmp/home XDG_DATA_HOME=$tmp/data XDG_CONFIG_HOME=$tmp/config XDG_DATA_DIRS=$tmp/system
mkdir -p "$HOME"
failed=0
check()   { if eval "$2"; then echo "  ok   $1"; else echo "  FAIL $1"; failed=1; fi; }
exit_is() { "$cli" "${@:2}" >/dev/null 2>&1; [ $? -eq "$1" ]; }
# Waits until process $1 runs with $2 in its arguments: a fake Claude started with & needs a moment.
started() { for _ in $(seq 100); do [[ $(ps -ww -p "$1" -o args= 2>/dev/null) == *"$2"* ]] && return 0; sleep 0.05; done; echo "       (process $1 never started)"; return 1; }

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
sum=$(md5sum < "$XDG_DATA_HOME/multi-claude/profiles/Work/icon.png")
ino=$(stat -c %i "$entry")
check 'add in another case changes that profile' 'exit_is 0 add work --color red && grep -qx "Name=Claude Work" "$entry" && grep -q " open Work$" "$entry" && [ "$(md5sum < "$XDG_DATA_HOME/multi-claude/profiles/Work/icon.png")" != "$sum" ] && [ ! -e "$XDG_CONFIG_HOME/Claude-work" ] && [ "$("$cli" list | grep -c .)" = 1 ]'
check 'add writes the launcher aside, then moves it in' '[ "$(stat -c %i "$entry")" != "$ino" ] && [ "$(stat -c %a "$entry")" = 644 ] && [ -z "$(ls -A "$XDG_DATA_HOME/applications" | grep "^\.")" ]'
check 'list shows the profile'                'grep -q "^Work " <<<"$("$cli" list)"'
check 'removing an unknown profile exits 1'   'exit_is 1 remove Nope'
check 'remove finds the profile in any case'  'out=$("$cli" remove work) && [ ! -f "$entry" ] && [ ! -d "$XDG_DATA_HOME/multi-claude/profiles/Work" ] && grep -qx "Removed Claude Work. Remove its icon from the dock if you pinned it." <<<"$out"'

# Claude Code: the profile's own config folder lives in its data folder, and that folder is the record.
shared=$HOME/.claude; own=$XDG_CONFIG_HOME/Claude-Code/.claude
id=0b6f6a52-1d3a-4d8e-9a43-6b2a0a8f5c11
mkdir -p "$shared/skills/mine" "$shared/agents" "$shared/projects/-work/$id/tool-results" "$shared/file-history/$id" "$shared/projects/-work/x"
echo '{"model": "opus"}' > "$shared/settings.json"; echo 'my rules' > "$shared/CLAUDE.md"
echo transcript > "$shared/projects/-work/$id.jsonl"; echo other > "$shared/projects/-work/other.jsonl"
echo secret > "$shared/.credentials.json"; echo '{"oauthAccount": {}}' > "$HOME/.claude.json"
snapshot() { (cd "$HOME" && find .claude .claude.json -exec ls -ld --time-style=+%s {} + | sort; cat .claude/settings.json .claude/CLAUDE.md) | md5sum; }
before=$(snapshot)
code_of() { "$cli" list | awk -v n="$1" '$1 == n { print ($2 == "running" ? $3 : $2) }'; }
check 'a new profile gets its own Claude Code'   'exit_is 0 add Fresh && [ -d "$XDG_CONFIG_HOME/Claude-Fresh/.claude" ] && [ "$(code_of Fresh)" = own ] && [ -z "$(ls -A "$XDG_CONFIG_HOME/Claude-Fresh/.claude")" ]'
mkdir -p "$XDG_CONFIG_HOME/Claude-Code/claude-code-sessions/acct/org"
printf '{"sessionId":"local_1","cliSessionId":"%s","cwd":"/work"}' "$id" > "$XDG_CONFIG_HOME/Claude-Code/claude-code-sessions/acct/org/local_1.json"
printf '{"cliSessionId": "../../x"}' > "$XDG_CONFIG_HOME/Claude-Code/claude-code-sessions/acct/org/local_2.json"
check 'an existing profile keeps sharing ~/.claude' 'exit_is 0 add Code && [ "$(code_of Code)" = shared ] && [ ! -e "$own" ] && exit_is 0 add Code --color red && [ "$(code_of Code)" = shared ]'
check 'unknown Claude Code mode exits 64'        'exit_is 64 add Code --claude-code banana && grep -qx "Unknown Claude Code mode '"'banana'"'. Use own, synced or shared." <<<"$("$cli" add Code --claude-code banana 2>&1)"'
check 'missing Claude Code mode exits 64'        'exit_is 64 add Code --claude-code'
check 'synced links the customizations'          'exit_is 0 add Code --claude-code Synced && [ "$(code_of Code)" = synced ] && [ "$(readlink "$own/skills")" = "$shared/skills" ] && [ "$(readlink "$own/agents")" = "$shared/agents" ] && [ ! -e "$own/commands" ] && [ ! -L "$own/commands" ]'
check 'CLAUDE.md imports the shared one'         '[ "$(cat "$own/CLAUDE.md")" = "@~/.claude/CLAUDE.md" ]'
check 'settings.json is copied, not linked'      '[ -f "$own/settings.json" ] && [ ! -L "$own/settings.json" ] && cmp -s "$own/settings.json" "$shared/settings.json"'
check 'sign-ins and account state stay behind'   '[ ! -e "$own/.credentials.json" ] && [ ! -e "$own/.claude.json" ] && [ ! -e "$XDG_CONFIG_HOME/Claude-Code/.claude.json" ]'
check "the profile's sessions are copied"        '[ "$(cat "$own/projects/-work/$id.jsonl")" = transcript ] && [ -d "$own/projects/-work/$id/tool-results" ] && [ -d "$own/file-history/$id" ]'
check "other sessions and bad ids are not"       '[ ! -e "$own/projects/-work/other.jsonl" ] && [ ! -e "$own/projects/-work/x" ] && [ ! -e "$XDG_CONFIG_HOME/x" ] && [ ! -e "$own/x" ]'
check 'the shared ~/.claude stays as it was'      '[ "$(snapshot)" = "$before" ]'
echo '{"theme": "mine"}' > "$own/settings.json"; echo changed > "$own/projects/-work/$id.jsonl"
check 'running add again keeps what the profile has' 'exit_is 0 add Code --claude-code synced && grep -q mine "$own/settings.json" && [ "$(cat "$own/projects/-work/$id.jsonl")" = changed ]'
check 'own drops only the links'                 'exit_is 0 add Code --claude-code own && [ "$(code_of Code)" = own ] && [ ! -e "$own/skills" ] && [ ! -e "$own/CLAUDE.md" ] && [ -d "$shared/skills/mine" ] && [ "$(cat "$shared/CLAUDE.md")" = "my rules" ] && grep -q mine "$own/settings.json"'
mkdir -p "$own/skills/profile-only"
check "synced keeps the profile's own folders"   'exit_is 0 add Code --claude-code synced && [ ! -L "$own/skills" ] && [ -d "$own/skills/profile-only" ] && [ -L "$own/agents" ]'
check 'shared parks the folder'                  'exit_is 0 add Code --claude-code shared && [ "$(code_of Code)" = shared ] && [ ! -e "$own" ] && [ -d "$own.off/projects" ]'
check 'own brings it back'                       'exit_is 0 add Code --claude-code own && [ "$(cat "$own/projects/-work/$id.jsonl")" = changed ] && [ ! -e "$own.off" ]'
mkdir "$own.off"
check 'shared refuses a parked folder in the way' 'exit_is 1 add Code --claude-code shared && [ -d "$own" ] && grep -q "already exists: move it aside first" <<<"$("$cli" add Code --claude-code shared 2>&1)"'
rmdir "$own.off"
exit_is 0 add Code --claude-code shared; mkdir -p "$own.new/projects"; : > "$own.new/projects/stale"   # an interrupted copy
check 'a leftover .claude.new goes once the parked folder is back' 'exit_is 0 add Code --claude-code own && [ -d "$own/projects/-work" ] && [ ! -e "$own.new" ] && [ ! -e "$own.off" ]'
rm -rf "$own"; echo '{"env": {"ANTHROPIC_API_KEY": "x"}}' > "$shared/settings.json"; before=$(snapshot)
mkdir -p "$own.new"; : > "$own.new/projects"   # a file in the way stops the copy
check 'a copy that stops halfway leaves it shared' 'exit_is 1 add Code --claude-code own && [ "$(code_of Code)" = shared ] && grep -q "^Could not copy" <<<"$("$cli" add Code --claude-code own 2>&1)"'
rm "$own.new/projects"
check 'add goes on from there'                   'exit_is 0 add Code --claude-code own && [ "$(cat "$own/projects/-work/$id.jsonl")" = transcript ] && [ -d "$own/projects/-work/$id/tool-results" ] && [ ! -e "$own.new" ]'
rm -rf "$own"
check 'settings with an env block are not copied' 'grep -q "was not copied: it has an env block" <<<"$("$cli" add Code --claude-code synced)" && [ ! -e "$own/settings.json" ] && [ "$(snapshot)" = "$before" ]'
bash -c 'sleep 30; :' _ "--user-data-dir=$XDG_CONFIG_HOME/Claude-Code" & running=$!
started "$running" "--user-data-dir=$XDG_CONFIG_HOME/Claude-Code"
check 'the mode does not change while it runs'   'exit_is 1 add Code --claude-code shared && [ -d "$own" ] && grep -q "^Quit Claude Code first" <<<"$("$cli" add Code --claude-code shared 2>&1)"'
check 'but it recolors'                          'exit_is 0 add Code --color teal && exit_is 0 add Code --claude-code own'
icon=$(grep -m1 '^Icon=' "$XDG_DATA_HOME/applications/multi-claude-code.desktop" | cut -d= -f2-); sum=$(md5sum < "$icon")
check 'changing the mode keeps the color'        'exit_is 0 add Code --claude-code synced && exit_is 0 add Code --claude-code own && [ "$(md5sum < "$icon")" = "$sum" ]'
kill "$running"; wait "$running" 2>/dev/null
# open: a fake Claude that writes down its environment and arguments.
mkdir -p "$tmp/bin"; dump=$tmp/open.dump
printf '#!/bin/sh\n{ env; for a in "$@"; do echo "ARG $a"; done; } > '\''%s.part'\'' && mv '\''%s.part'\'' '\''%s'\''\n' "$dump" "$dump" "$dump" > "$tmp/bin/fake-claude"
chmod +x "$tmp/bin/fake-claude"
sed -i "s#^Exec=.*#Exec=\"$tmp/bin/fake-claude\" %U#" "$XDG_DATA_HOME/applications/claude-desktop.desktop"
opened() { rm -f "$dump"; CLAUDE_CONFIG_DIR=/inherited CLAUDECODE=1 "$cli" open "$1" || return 1; for _ in $(seq 50); do [ -f "$dump" ] && return 0; sleep 0.1; done; return 1; }
check 'open runs Code on the own folder'          'opened Code && grep -qx "CLAUDE_CONFIG_DIR=$own" "$dump" && grep -qx "ARG --user-data-dir=$XDG_CONFIG_HOME/Claude-Code" "$dump" && ! grep -q "^CLAUDECODE=" "$dump"'
check 'open leaves a shared profile on ~/.claude' 'exit_is 0 add Code --claude-code shared && opened Code && ! grep -q "^CLAUDE_CONFIG_DIR=" "$dump"'
check 'doctor names an inherited CLAUDE_CONFIG_DIR' 'grep -q "^CLAUDE_CONFIG_DIR: /x in this terminal; open drops it: each profile uses its own folder or ~/.claude$" <<<"$(CLAUDE_CONFIG_DIR=/x "$cli" doctor)"'
check 'remove keeps the Claude Code folder'      'exit_is 0 add Code --claude-code own && exit_is 0 remove Code && exit_is 0 remove Fresh && [ -d "$own/projects" ]'
sed -i "s#^Exec=.*#Exec=/usr/bin/claude-desktop %U#" "$XDG_DATA_HOME/applications/claude-desktop.desktop"
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

# ~/.local/bin/multi-claude: uninstall removes only its own link, never a real file.
bin=$HOME/.local/bin/multi-claude
mkdir -p "${bin%/*}"; cp "$cli" "$bin"
touch "$XDG_DATA_HOME/applications/.multi-claude-two.abc123"   # an interrupted add
check 'uninstall cleans up'                   'exit_is 0 add Two && exit_is 0 uninstall && [ ! -d "$XDG_DATA_HOME/multi-claude" ] && ! ls -A "$XDG_DATA_HOME/applications" | grep -q multi-claude'
check 'uninstall keeps sign-ins and Claude Code' '[ -d "$XDG_CONFIG_HOME/Claude-Two/.claude" ] && [ -d "$XDG_CONFIG_HOME/Claude-Code/.claude/projects" ]'
check 'uninstall leaves a real ~/.local/bin/multi-claude alone' '[ -f "$bin" ] && [ ! -L "$bin" ]'
rm -f "$bin"; mkdir -p "$XDG_DATA_HOME/multi-claude/lib"; cp "$cli" "$XDG_DATA_HOME/multi-claude/lib/multi-claude"
if ln -s "$XDG_DATA_HOME/multi-claude/lib/multi-claude" "$bin" 2>/dev/null && [ -L "$bin" ]; then
  check 'uninstall removes its own link'      'exit_is 0 uninstall && [ ! -e "$bin" ] && [ ! -L "$bin" ]'
else
  echo '  skip uninstall removes its own link (no symlinks here)'
fi
if [ $failed -eq 0 ]; then echo 'all tests passed'; fi
exit $failed
