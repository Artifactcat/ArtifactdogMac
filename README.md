# Artifactdog's macOS setup

A reproducible Linux-style macOS rice built around AeroSpace, JankyBorders,
Ghostty, Karabiner-Elements, and the native macOS menu bar.

## Install

Prerequisite: macOS and [Homebrew](https://brew.sh). Then run one command from
the checkout:

```bash
./install.sh
```

The installer installs the required packages, backs up existing managed
configuration, copies this repository's configuration into `~/.config`, and
starts AeroSpace and JankyBorders. It also removes the old Yabai/skhd and
custom Space-indicator setup when those legacy files are present.

Afterward, follow the short manual checklist in
[POST-INSTALL.md](POST-INSTALL.md). The most important steps are granting
macOS permissions and enabling the Karabiner Hyper-key rule.

## Read next

- [HOTKEYS.md](HOTKEYS.md) — the everyday shortcut cheat sheet.
- [POST-INSTALL.md](POST-INSTALL.md) — permissions, verification, and known
  behavior.
- `config/` — the source-of-truth configuration copied by the installer.
- `scripts/install-terminal-banner.sh` — installs the neofetch wrapper and
  live CAVA equalizer used by new interactive zsh sessions.
- `scripts/install-allow-helper.sh` — installs the `allow` zsh alias for
  removing the download quarantine marker from a trusted app.
- `Brewfile` — the Homebrew dependencies used by `install.sh`.

## Design choices

- AeroSpace provides tiling, focus, virtual workspaces, and hotkeys.
- JankyBorders provides the focused/inactive colored window outlines; it is a
  visual layer, not another window manager.
- Ghostty is transparent and uses native macOS blur.
- New interactive zsh sessions keep the neofetch banner and add a live,
  monochrome three-row audio-reactive equalizer with 21 wider columns and gaps
  between them, inset two characters from neofetch's left edge while Spotify
  is open, followed by a now-playing artist/title line and spacing before the
  prompt. It samples at 60 FPS and uses 24 fractional height levels across
  the three rows, with fast attack and eased decay for smooth motion.
- CAVA reads the macOS system-output mix through CoreAudio tap support; the
  bars are driven by audio levels, not Spotify track metadata.
- The native menu bar stays enabled. Native macOS Spaces are not required;
  AeroSpace workspaces avoid their system Space-switch animation.
- No SIP change is required. This setup does not use Yabai, skhd, or a custom
  menu-bar Space indicator.
- The `allow` helper only removes `com.apple.quarantine` from an explicitly
  supplied path; it does not bypass malware detection or privacy permissions.
- The current layout uses 12px inner/side/bottom gaps, a 7px top gap, and 7px
  borders.

AeroSpace intentionally moves inactive-workspace windows out of the active
area rather than using native Spaces. On some macOS versions a tiny corner can
remain visible; completely hiding those windows requires native Spaces and
their system-managed transition behavior.

## Useful links

- [AeroSpace guide](https://nikitabobko.github.io/AeroSpace/guide)
- [AeroSpace repository](https://github.com/nikitabobko/AeroSpace)
- [JankyBorders repository](https://github.com/FelixKratz/JankyBorders)
- [Ghostty documentation](https://ghostty.org/docs)
- [Karabiner-Elements documentation](https://karabiner-elements.pqrs.org/docs/)
- [Homebrew](https://brew.sh)
