#!/usr/bin/env bash
set -euo pipefail

if [ "$(uname -s)" != "Darwin" ]; then
  echo "This setup is for macOS only."
  exit 1
fi

if ! command -v brew >/dev/null 2>&1; then
  echo "Homebrew is required. Install it from https://brew.sh and rerun this script."
  exit 1
fi

ROOT="$(cd "$(dirname "$0")" && pwd)"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP="$HOME/.config/artifactdog-macos-setup-backup-$STAMP"
UID_VALUE="$(id -u)"
mkdir -p "$BACKUP"

backup_and_copy_dir() {
  local name="$1"
  local src="$ROOT/config/$name"
  local dst="$HOME/.config/$name"
  if [ -e "$dst" ] || [ -L "$dst" ]; then
    echo "Backing up $dst -> $BACKUP/$name"
    mv "$dst" "$BACKUP/$name"
  fi
  mkdir -p "$(dirname "$dst")"
  cp -R "$src" "$dst"
}

backup_and_copy_file() {
  local src="$1"
  local dst="$2"
  local backup_name="$3"
  if [ -e "$dst" ] || [ -L "$dst" ]; then
    echo "Backing up $dst -> $BACKUP/$backup_name"
    mv "$dst" "$BACKUP/$backup_name"
  fi
  mkdir -p "$(dirname "$dst")"
  cp "$src" "$dst"
}

backup_and_remove() {
  local path="$1"
  local backup_name="$2"
  if [ -e "$path" ] || [ -L "$path" ]; then
    echo "Removing legacy path after backup: $path"
    mv "$path" "$BACKUP/$backup_name"
  fi
}

stop_legacy_service() {
  local command_name="$1"
  if command -v "$command_name" >/dev/null 2>&1; then
    "$command_name" --stop-service >/dev/null 2>&1 || true
  fi
}

echo "Switching to AeroSpace and removing the legacy Yabai/skhd stack..."

# Stop and detach the previous tiler, hotkey daemon, and custom menu-bar item
# before replacing their files. Existing paths are moved into this run's
# backup directory so a failed migration is recoverable.
stop_legacy_service yabai
stop_legacy_service skhd
launchctl bootout "gui/$UID_VALUE/com.asmvik.yabai" >/dev/null 2>&1 || true
launchctl bootout "gui/$UID_VALUE/com.koekeishiya.skhd" >/dev/null 2>&1 || true
launchctl bootout "gui/$UID_VALUE/com.artifactdog.macos-setup.space-indicator" >/dev/null 2>&1 || true

backup_and_remove "$HOME/.yabairc" yabairc
backup_and_remove "$HOME/.config/skhd" skhd
backup_and_remove "$HOME/.local/bin/artifactdog-space-indicator" artifactdog-space-indicator
backup_and_remove "$HOME/Library/LaunchAgents/com.asmvik.yabai.plist" com.asmvik.yabai.plist
backup_and_remove "$HOME/Library/LaunchAgents/com.koekeishiya.skhd.plist" com.koekeishiya.skhd.plist
backup_and_remove "$HOME/Library/LaunchAgents/com.artifactdog.macos-setup.space-indicator.plist" com.artifactdog.macos-setup.space-indicator.plist
backup_and_remove "$HOME/Library/Caches/artifactdog-space-indicator-swift" artifactdog-space-indicator-swift

for formula in yabai skhd; do
  if brew list --formula "$formula" >/dev/null 2>&1; then
    brew uninstall --formula "$formula"
  fi
done

# The asmvik/formulae tap is no longer needed unless krp is installed.
if brew tap | grep -Fxq 'asmvik/formulae'; then
  if ! brew list --formula krp >/dev/null 2>&1; then
    brew untap asmvik/formulae >/dev/null 2>&1 || true
  fi
fi

echo "Installing the dependencies listed in Brewfile..."
bash -n \
  "$ROOT/install.sh" \
  "$ROOT"/config/aerospace/*.sh \
  "$ROOT/scripts/install-terminal-banner.sh" \
  "$ROOT/scripts/install-allow-helper.sh"
zsh -n "$ROOT/config/zsh/artifactdog-terminal-equalizer.zsh"
brew bundle --file="$ROOT/Brewfile"

if [ "$(uname -m)" = "arm64" ]; then
  if ! brew list --cask raycast >/dev/null 2>&1; then
    brew install --cask raycast
  fi
else
  echo "Skipping Raycast Homebrew install on Intel. Install a compatible Raycast build manually if desired."
fi

backup_and_copy_dir aerospace
backup_and_copy_dir borders
backup_and_copy_dir cava
backup_and_copy_dir ghostty
backup_and_copy_file \
  "$ROOT/karabiner/artifactdog-hyper.json" \
  "$HOME/.config/karabiner/assets/complex_modifications/artifactdog-hyper.json" \
  artifactdog-hyper.json

bash "$ROOT/scripts/install-terminal-banner.sh"
bash "$ROOT/scripts/install-allow-helper.sh"

# Keep the separate Globe/Fn key available for language switching. This does
# not change the Caps Lock -> Hyper mapping used by AeroSpace.
defaults write com.apple.HIToolbox AppleFnUsageType -int 1

chmod +x \
  "$HOME/.config/borders/bordersrc" \
  "$HOME/.config/aerospace/quit-focused-app.sh" \
  "$HOME/.config/aerospace/open-finder.sh" \
  "$HOME/.config/aerospace/reload-borders.sh" \
  "$HOME/.config/aerospace/restart-window-stack.sh" \
  "$HOME/.config/aerospace/smart-open-ghostty.sh" \
  "$HOME/.config/aerospace/smart-place-window.sh"

brew services restart borders
open -a AeroSpace
open -a Karabiner-Elements || true

echo
echo "AeroSpace is active. Existing configs (if any) were moved to: $BACKUP"
echo "Now read POST-INSTALL.md for the few macOS permission/settings steps."
