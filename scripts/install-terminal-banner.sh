#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
STAMP="$(date +%Y%m%d-%H%M%S)"
CONFIG_DIR="$HOME/.config/artifactdog"
CAVA_CONFIG_DIR="$HOME/.config/cava"
BIN_DIR="$HOME/.local/bin"
ZSHRC="$HOME/.zshrc"
MARKER_START='# >>> Artifactdog terminal banner >>>'
MARKER_END='# <<< Artifactdog terminal banner <<<'

mkdir -p "$CONFIG_DIR" "$CAVA_CONFIG_DIR" "$BIN_DIR"
cp "$ROOT/config/zsh/artifactdog-terminal-equalizer.zsh" "$CONFIG_DIR/terminal-equalizer.zsh"
cp "$ROOT/config/cava/config" "$CAVA_CONFIG_DIR/config"
cp "$ROOT/config/bin/artifactdog-terminal-banner" "$BIN_DIR/artifactdog-terminal-banner"
chmod +x "$BIN_DIR/artifactdog-terminal-banner"

if [ ! -f "$ZSHRC" ]; then
  touch "$ZSHRC"
fi

backup=''
if grep -Fq "$MARKER_START" "$ZSHRC" || grep -Fxq 'neofetch' "$ZSHRC"; then
  backup="$CONFIG_DIR/zshrc-backup-$STAMP"
  cp "$ZSHRC" "$backup"
fi

if [ -n "$backup" ] || ! grep -Fq "$MARKER_START" "$ZSHRC"; then
  temp_file="$(mktemp "${TMPDIR:-/tmp}/artifactdog-zshrc.XXXXXX")"
  cleanup() {
    rm -f "$temp_file"
  }
  trap cleanup EXIT

  awk -v start="$MARKER_START" -v end="$MARKER_END" '\
    BEGIN { in_block = 0; found = 0 }
    $0 == start {
      print start
      print "if [[ -o interactive ]]; then"
      print "  \"$HOME/.local/bin/artifactdog-terminal-banner\""
      print "  source \"$HOME/.config/artifactdog/terminal-equalizer.zsh\""
      print "fi"
      in_block = 1
      found = 1
      next
    }
    in_block && $0 == end { print end; in_block = 0; next }
    !in_block && $0 != "neofetch" { print }
    END {
      if (!found) {
        print ""
        print start
        print "if [[ -o interactive ]]; then"
        print "  \"$HOME/.local/bin/artifactdog-terminal-banner\""
        print "  source \"$HOME/.config/artifactdog/terminal-equalizer.zsh\""
        print "fi"
        print end
      }
    }
  ' "$ZSHRC" > "$temp_file"
  mv "$temp_file" "$ZSHRC"
fi

echo "Installed Artifactdog terminal banner configuration."
