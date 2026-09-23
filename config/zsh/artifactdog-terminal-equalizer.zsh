# Artifactdog's live terminal equalizer.
#
# This file is sourced from .zshrc. CAVA reads the macOS system-output mix
# through its CoreAudio tap and this zsh line-editor handler redraws a full
# multi-row spectrum directly below the neofetch banner.

if [[ -n "${ARTIFACTDOG_EQUALIZER_STARTED:-}" ]]; then
  return
fi

if (( ! $+commands[cava] )); then
  return
fi

spotify_running="$(/usr/bin/osascript -l JavaScript -e '
  ObjC.import("Foundation");
  const spotify = Application("com.spotify.client");
  const line = (spotify.running() ? "1" : "0") + "\n";
  const data = $(line).dataUsingEncoding($.NSUTF8StringEncoding);
  $.NSFileHandle.fileHandleWithStandardOutput.writeData(data);
' 2>/dev/null)" || spotify_running=0
[[ "$spotify_running" == 1 ]] || return

typeset -g ARTIFACTDOG_EQUALIZER_STARTED=1
typeset -g ARTIFACTDOG_EQUALIZER_PROMPT=''
typeset -g ARTIFACTDOG_EQUALIZER_DIR=''
typeset -g ARTIFACTDOG_EQUALIZER_FD=''
typeset -g ARTIFACTDOG_EQUALIZER_PID=''
typeset -g ARTIFACTDOG_EQUALIZER_METADATA_FIFO=''
typeset -g ARTIFACTDOG_EQUALIZER_METADATA_FD=''
typeset -g ARTIFACTDOG_EQUALIZER_METADATA_PID=''
typeset -g ARTIFACTDOG_EQUALIZER_BASE_PROMPT="${PROMPT:-}"
typeset -g ARTIFACTDOG_EQUALIZER_BASE_RPROMPT="${RPROMPT:-}"
typeset -gi ARTIFACTDOG_EQUALIZER_ROWS=3
typeset -gi ARTIFACTDOG_EQUALIZER_BARS=21
typeset -g ARTIFACTDOG_EQUALIZER_INDENT='  '
typeset -g ARTIFACTDOG_EQUALIZER_NOW_PLAYING='♫  Now playing: Spotify'
typeset -ga ARTIFACTDOG_EQUALIZER_LEVELS=()
typeset -ga ARTIFACTDOG_EQUALIZER_GLYPHS=(' ' '▁' '▂' '▃' '▄' '▅' '▆' '▇' '█')

artifactdog_equalizer_fetch_now_playing() {
  /usr/bin/osascript -l JavaScript -e '
    ObjC.import("Foundation");
    const spotify = Application("com.spotify.client");
    let line = "";
    try {
      if (spotify.running()) {
        const track = spotify.currentTrack();
        line = String(track.artist()) + "\t" + String(track.name()) + "\n";
      }
    } catch (error) {}
    const data = $(line).dataUsingEncoding($.NSUTF8StringEncoding);
    $.NSFileHandle.fileHandleWithStandardOutput.writeData(data);
  ' 2>/dev/null
}

artifactdog_equalizer_apply_now_playing() {
  local metadata="$1" artist title

  [[ "$metadata" == *$'\t'* ]] || return
  artist="${metadata%%$'\t'*}"
  title="${metadata#*$'\t'}"
  title="${title%$'\n'}"
  [[ -n "$artist" && -n "$title" ]] || return
  artist="${artist//\%/%%}"
  title="${title//\%/%%}"
  ARTIFACTDOG_EQUALIZER_NOW_PLAYING="♫  Now playing: ${artist} — ${title}"
}

artifactdog_equalizer_metadata_worker() {
  local metadata_fifo="$1" metadata

  while true; do
    metadata="$(artifactdog_equalizer_fetch_now_playing)" || metadata=''
    print -r -- "$metadata" >| "$metadata_fifo" || return
    sleep 2
  done
}

artifactdog_equalizer_render_frame() {
  local frame="$1"
  local value level previous peak=0 row column line output='' newline=$'\n' glyph
  local -a levels smoothed

  levels=("${(@s/;/)frame}")
  for value in "${levels[@]}"; do
    [[ "$value" == <-> ]] || continue
    (( value > peak )) && peak=$value
  done

  for (( column = 1; column <= ARTIFACTDOG_EQUALIZER_BARS; column++ )); do
    value="${levels[$column]:-0}"
    [[ "$value" == <-> ]] || value=0
    if (( peak < 10 || value * 100 <= peak * 20 )); then
      level=0
    else
      level=$(( (value * 100 - peak * 20) * 24 / (peak * 80) ))
      (( level > 24 )) && level=24
    fi
    previous="${ARTIFACTDOG_EQUALIZER_LEVELS[$column]:-0}"
    if (( level < previous )); then
      level=$(( (previous * 3 + level) / 4 ))
    fi
    ARTIFACTDOG_EQUALIZER_LEVELS[$column]=$level
    smoothed[$column]=$level
  done

  for (( row = ARTIFACTDOG_EQUALIZER_ROWS; row >= 1; row-- )); do
    line="${ARTIFACTDOG_EQUALIZER_INDENT}"
    for (( column = 1; column <= ARTIFACTDOG_EQUALIZER_BARS; column++ )); do
      level="${smoothed[$column]:-0}"
      if (( level >= row * 8 )); then
        glyph='█'
      elif (( level > (row - 1) * 8 )); then
        glyph="${ARTIFACTDOG_EQUALIZER_GLYPHS[$((level - (row - 1) * 8 + 1))]}"
      else
        glyph=' '
      fi
      if [[ "$glyph" == ' ' ]]; then
        line+='  '
      else
        line+="${glyph}${glyph}"
      fi
      line+=' '
    done
    line+=' '
    output+="${line}${newline}"
  done
  output="${output%$'\n'}"
  typeset -g ARTIFACTDOG_EQUALIZER_PROMPT="$output"
}

artifactdog_equalizer_read_frame() {
  local fd="$1"
  local frame

  if IFS= read -r -u "$fd" frame; then
    artifactdog_equalizer_render_frame "$frame"
    typeset -g PROMPT="${ARTIFACTDOG_EQUALIZER_PROMPT}"$'\n'"${ARTIFACTDOG_EQUALIZER_INDENT}${ARTIFACTDOG_EQUALIZER_NOW_PLAYING}"$'\n\n'"${ARTIFACTDOG_EQUALIZER_BASE_PROMPT}"
    zle reset-prompt
  else
    zle -F "$fd" 2>/dev/null || true
    exec {fd}<&- 2>/dev/null || true
  fi
}

artifactdog_equalizer_read_metadata() {
  local fd="$1"
  local metadata

  if IFS= read -r -u "$fd" metadata; then
    artifactdog_equalizer_apply_now_playing "$metadata"
    typeset -g PROMPT="${ARTIFACTDOG_EQUALIZER_PROMPT}"$'\n'"${ARTIFACTDOG_EQUALIZER_INDENT}${ARTIFACTDOG_EQUALIZER_NOW_PLAYING}"$'\n\n'"${ARTIFACTDOG_EQUALIZER_BASE_PROMPT}"
    zle reset-prompt
  else
    zle -F "$fd" 2>/dev/null || true
    exec {fd}<&- 2>/dev/null || true
  fi
}

artifactdog_equalizer_cleanup() {
  if [[ -n "$ARTIFACTDOG_EQUALIZER_METADATA_FD" ]]; then
    zle -F "$ARTIFACTDOG_EQUALIZER_METADATA_FD" 2>/dev/null || true
    exec {ARTIFACTDOG_EQUALIZER_METADATA_FD}<&- 2>/dev/null || true
  fi
  if [[ -n "$ARTIFACTDOG_EQUALIZER_METADATA_PID" ]]; then
    kill "$ARTIFACTDOG_EQUALIZER_METADATA_PID" 2>/dev/null || true
    wait "$ARTIFACTDOG_EQUALIZER_METADATA_PID" 2>/dev/null || true
  fi
  if [[ -n "$ARTIFACTDOG_EQUALIZER_FD" ]]; then
    zle -F "$ARTIFACTDOG_EQUALIZER_FD" 2>/dev/null || true
    exec {ARTIFACTDOG_EQUALIZER_FD}<&- 2>/dev/null || true
  fi
  if [[ -n "$ARTIFACTDOG_EQUALIZER_PID" ]]; then
    kill "$ARTIFACTDOG_EQUALIZER_PID" 2>/dev/null || true
    wait "$ARTIFACTDOG_EQUALIZER_PID" 2>/dev/null || true
  fi
  if [[ -n "$ARTIFACTDOG_EQUALIZER_DIR" && -d "$ARTIFACTDOG_EQUALIZER_DIR" ]]; then
    rm -rf -- "$ARTIFACTDOG_EQUALIZER_DIR"
  fi
  PROMPT="$ARTIFACTDOG_EQUALIZER_BASE_PROMPT"
  RPROMPT="$ARTIFACTDOG_EQUALIZER_BASE_RPROMPT"
  zle reset-prompt 2>/dev/null || true
}

ARTIFACTDOG_EQUALIZER_DIR="$(mktemp -d "${TMPDIR:-/tmp}/artifactdog-cava.XXXXXX")" || return
artifactdog_equalizer_fifo="$ARTIFACTDOG_EQUALIZER_DIR/frames"
mkfifo "$artifactdog_equalizer_fifo" || return

ARTIFACTDOG_EQUALIZER_METADATA_FIFO="$ARTIFACTDOG_EQUALIZER_DIR/metadata"
mkfifo "$ARTIFACTDOG_EQUALIZER_METADATA_FIFO" || return
artifactdog_equalizer_metadata_worker "$ARTIFACTDOG_EQUALIZER_METADATA_FIFO" &!
ARTIFACTDOG_EQUALIZER_METADATA_PID=$!
exec {ARTIFACTDOG_EQUALIZER_METADATA_FD}<"$ARTIFACTDOG_EQUALIZER_METADATA_FIFO" || return
zle -F "$ARTIFACTDOG_EQUALIZER_METADATA_FD" artifactdog_equalizer_read_metadata

cava -p "$HOME/.config/cava/config" >"$artifactdog_equalizer_fifo" \
  2>"$ARTIFACTDOG_EQUALIZER_DIR/cava.log" &!
ARTIFACTDOG_EQUALIZER_PID=$!
exec {ARTIFACTDOG_EQUALIZER_FD}<"$artifactdog_equalizer_fifo" || return
rm -f "$artifactdog_equalizer_fifo"

zle -F "$ARTIFACTDOG_EQUALIZER_FD" artifactdog_equalizer_read_frame
autoload -Uz add-zsh-hook
add-zsh-hook zshexit artifactdog_equalizer_cleanup

PROMPT="$ARTIFACTDOG_EQUALIZER_BASE_PROMPT"
RPROMPT="$ARTIFACTDOG_EQUALIZER_BASE_RPROMPT"
