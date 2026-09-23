#!/usr/bin/env bash
set -euo pipefail

ZSHRC="$HOME/.zshrc"
CONFIG_DIR="$HOME/.config/artifactdog"
STAMP="$(date +%Y%m%d-%H%M%S)"
MARKER_START='# >>> Artifactdog allow helper >>>'
MARKER_END='# <<< Artifactdog allow helper <<<'

mkdir -p "$CONFIG_DIR"
if [ ! -f "$ZSHRC" ]; then
  touch "$ZSHRC"
fi

if grep -Eq '^[[:space:]]*(alias[[:space:]]+allow|allow[[:space:]]*\(\))' "$ZSHRC" \
  && ! grep -Fq "$MARKER_START" "$ZSHRC"; then
  echo "Refusing to replace an existing allow command in $ZSHRC." >&2
  exit 1
fi

if ! grep -Fq "$MARKER_START" "$ZSHRC"; then
  backup="$CONFIG_DIR/zshrc-backup-$STAMP"
  cp "$ZSHRC" "$backup"
  temp_file="$(mktemp "${TMPDIR:-/tmp}/artifactdog-zshrc.XXXXXX")"
  cleanup() {
    rm -f "$temp_file"
  }
  trap cleanup EXIT

  cp "$ZSHRC" "$temp_file"
  {
    printf '\n%s\n' "$MARKER_START"
    printf '%s\n' "# Remove the download quarantine marker from a trusted app: allow \"/Applications/App.app\""
    printf '%s\n' "alias allow='/usr/bin/xattr -dr com.apple.quarantine'"
    printf '%s\n' "$MARKER_END"
  } >> "$temp_file"
  mv "$temp_file" "$ZSHRC"
fi

echo "Installed the Artifactdog allow alias in $ZSHRC."
