#!/bin/sh
# multi-claude installer for macOS and Linux.
#
#   curl -fsSL https://github.com/thomasog/multi-claude/releases/latest/download/install.sh | sh
#   ./install.sh                         (from a clone: installs that checkout)
#
# Installs the `multi-claude` command for the current user, no sudo: files go to
# ~/.local/share/multi-claude and the command is linked into ~/.local/bin. The release workflow stamps
# this file with its version and the archive's SHA-256, so the download is pinned and verified.
# Everything runs inside main(), so a partially downloaded script never runs.
set -eu

REPO=thomasog/multi-claude
VERSION=__VERSION__
SHA256=__SHA256__

main() {
  lib=${XDG_DATA_HOME:-$HOME/.local/share}/multi-claude/lib
  bin=$HOME/.local/bin
  case $(uname -s) in
    Darwin) os=macos ;;
    Linux)  os=linux ;;
    *) echo "Unsupported system: $(uname -s). On Windows, use install.ps1." >&2; exit 1 ;;
  esac

  # 1. The files: this checkout, or the pinned release archive checked against its SHA-256.
  here=
  if [ -f "$0" ]; then here=$(cd "$(dirname "$0")" && pwd); fi   # piped from curl, $0 is the shell
  if [ -n "$here" ] && [ -f "$here/src/$os/multi-claude" ]; then
    src=$here/src/$os
  else
    case $VERSION in __*) echo "This installer is not from a release. Run it from a clone, or use the release URL." >&2; exit 1 ;; esac
    tmp=$(mktemp -d)
    trap 'rm -rf "$tmp"' EXIT
    echo "Downloading multi-claude $VERSION ..."
    curl -fsSL "https://github.com/$REPO/releases/download/$VERSION/multi-claude.tar.gz" -o "$tmp/multi-claude.tar.gz"
    actual=$(if command -v sha256sum >/dev/null; then sha256sum "$tmp/multi-claude.tar.gz"; else shasum -a 256 "$tmp/multi-claude.tar.gz"; fi | cut -d' ' -f1)
    if [ "$actual" != "$SHA256" ]; then
      echo "Checksum mismatch (expected $SHA256, got $actual). Nothing was installed." >&2
      exit 1
    fi
    tar -xzf "$tmp/multi-claude.tar.gz" -C "$tmp"
    src=$tmp/src/$os
  fi

  # 2. The command. Each file is written aside, then moved into place, so a running multi-claude
  #    (a background watcher) keeps reading its old file instead of a half-written one.
  mkdir -p "$lib" "$bin"
  for file in "$src"/*; do
    if [ -f "$file" ]; then
      part=$lib/.$(basename "$file").part
      cp "$file" "$part"
      if [ "$(basename "$file")" = multi-claude ]; then chmod +x "$part"; fi
      mv -f "$part" "$lib/$(basename "$file")"
    fi
  done
  ln -sf "$lib/multi-claude" "$bin/multi-claude"
  echo
  echo "  multi-claude is installed. Add a profile with: multi-claude add Work --color blue"
  case :$PATH: in
    *:"$bin":*) ;;
    *) echo "  Add $bin to your PATH first, e.g. in ~/.zshrc or ~/.bashrc." ;;
  esac
  echo

  # 3. An extra profile, right away (reads the terminal even when piped from curl).
  #    The regular Claude is never touched.
  if (: </dev/tty) 2>/dev/null; then
    echo 'Your regular Claude stays exactly as it is. Now add an extra Claude for another account.' >/dev/tty
    printf 'Name for the extra Claude (e.g. Work), or press Enter to skip: ' >/dev/tty
    read -r name </dev/tty || name=
    if [ -n "$name" ]; then
      "$lib/multi-claude" add "$name" --color "$(pick_color)"
    fi
  fi
}

# Numbered color list with a swatch per color; a hex value can be typed instead.
pick_color() {
  i=0
  for entry in green:1F6F43 blue:1F4E8C purple:5B3A8E red:9B2C2C teal:146C6C pink:A0346B gray:4A4F57; do
    i=$((i + 1)); hex=${entry#*:}
    r=$((0x$(echo "$hex" | cut -c1-2))); g=$((0x$(echo "$hex" | cut -c3-4))); b=$((0x$(echo "$hex" | cut -c5-6)))
    printf '  %d \033[48;2;%d;%d;%dm    \033[0m %s\n' "$i" "$r" "$g" "$b" "${entry%%:*}" >/dev/tty
  done
  printf 'Color: a number above, or a hex like C0392B [1]: ' >/dev/tty
  read -r choice </dev/tty || choice=
  case ${choice:-1} in
    1) echo green ;; 2) echo blue ;; 3) echo purple ;; 4) echo red ;;
    5) echo teal ;; 6) echo pink ;; 7) echo gray ;; *) echo "$choice" ;;
  esac
}

main "$@"
