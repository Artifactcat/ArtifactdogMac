# Artifactdog's live terminal equalizer and Spotify track line.
#
# Sourced from .zshrc right after the neofetch banner. CAVA reads the macOS
# system-output mix through its CoreAudio tap. zle file-descriptor handlers
# repaint the three bar rows and the now-playing line *in place* below the
# banner, using absolute cursor positioning wrapped in save/restore-cursor.
# The prompt itself is never modified, so typing is never blocked and the bars
# never follow the command line.
#
# The bars animate whenever zsh is waiting at a prompt and pause while a
# command runs. zle hooks keep their position honest: at every new prompt,
# after any widget that can draw below the command line (completion lists,
# searches), and every couple of seconds while typing, they ask the terminal
# where the cursor is (CSI 6n) and confirm the screen has not scrolled, been
# cleared, or been resized. As soon as the bars' position can no longer be
# proven, CAVA and the track poller stop and the last frame stays behind like
# the rest of the banner (in practice: once output pushes the banner up).

[[ -n "${ARTIFACTDOG_EQUALIZER_STARTED:-}" ]] && return

# Claude Desktop starts a shell for every chat. cava there asks macOS for System
# Audio Recording, which Claude does not have, so System Settings opens each time.
[[ "${__CFBundleIdentifier:-}" == "com.anthropic.claudefordesktop" ]] && return

[[ -o interactive && -o zle && -t 0 && -t 1 ]] || return
(( $+commands[cava] )) || return

spotify_running="$(/usr/bin/osascript -l JavaScript -e '
  ObjC.import("Foundation");
  const spotify = Application("com.spotify.client");
  const line = (spotify.running() ? "1" : "0") + "\n";
  const data = $(line).dataUsingEncoding($.NSUTF8StringEncoding);
  $.NSFileHandle.fileHandleWithStandardOutput.writeData(data);
' 2>/dev/null)" || spotify_running=0
[[ "$spotify_running" == 1 ]] || { unset spotify_running; return }
unset spotify_running

zmodload zsh/datetime 2>/dev/null || return
autoload -Uz add-zsh-hook add-zle-hook-widget

typeset -g ARTIFACTDOG_EQUALIZER_STARTED=1
typeset -gi ARTIFACTDOG_EQUALIZER_ACTIVE=0
typeset -g ARTIFACTDOG_EQUALIZER_DIR=''
typeset -g ARTIFACTDOG_EQUALIZER_FD=''
typeset -g ARTIFACTDOG_EQUALIZER_PID=''
typeset -g ARTIFACTDOG_EQUALIZER_META_FD=''
typeset -g ARTIFACTDOG_EQUALIZER_META_PID=''
typeset -g ARTIFACTDOG_EQUALIZER_NOW_PLAYING='♫  Now playing: Spotify'
typeset -g ARTIFACTDOG_EQUALIZER_PAINTED=''
typeset -gi ARTIFACTDOG_EQUALIZER_ROWS=3
typeset -gi ARTIFACTDOG_EQUALIZER_BARS=21
typeset -g ARTIFACTDOG_EQUALIZER_INDENT='  '
typeset -ga ARTIFACTDOG_EQUALIZER_GLYPHS=(' ' '▁' '▂' '▃' '▄' '▅' '▆' '▇' '█')
typeset -ga ARTIFACTDOG_EQUALIZER_LEVELS=()
typeset -ga ARTIFACTDOG_EQUALIZER_FRAME=()
# Screen geometry: TOP is the terminal row of the first bar row, PROMPT_ROW the
# row the current prompt starts on. Both are only trusted while the terminal
# size is unchanged and the cursor checks below keep agreeing with them.
typeset -gi ARTIFACTDOG_EQUALIZER_TOP=0
typeset -gi ARTIFACTDOG_EQUALIZER_PROMPT_ROW=0
typeset -gi ARTIFACTDOG_EQUALIZER_ANCHOR_COLUMNS=0
typeset -gi ARTIFACTDOG_EQUALIZER_ANCHOR_LINES=0
typeset -gi ARTIFACTDOG_EQUALIZER_CURSOR_ROW=0
typeset -gi ARTIFACTDOG_EQUALIZER_PAUSED=1
typeset -gi ARTIFACTDOG_EQUALIZER_NEW_PROMPT=1
typeset -gi ARTIFACTDOG_EQUALIZER_FIRST_PROMPT=1
typeset -gF ARTIFACTDOG_EQUALIZER_LAST_CHECK=0
# Text before the cursor as of the last redraw.
typeset -g ARTIFACTDOG_EQUALIZER_SHOWN=''

artifactdog_equalizer_width() {
  REPLY=$(( ${#ARTIFACTDOG_EQUALIZER_INDENT} + ARTIFACTDOG_EQUALIZER_BARS * 3 + 1 ))
}

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
  ARTIFACTDOG_EQUALIZER_NOW_PLAYING="♫  Now playing: ${artist} — ${title}"
}

# Runs in the background: prints "artist<TAB>title" every few seconds. It exits
# (and takes CAVA with it) once the owning shell is gone.
artifactdog_equalizer_metadata_worker() {
  local shell_pid="$1" cava_pid="$2" metadata

  while kill -0 "$shell_pid" 2>/dev/null; do
    metadata="$(artifactdog_equalizer_fetch_now_playing)" || metadata=''
    print -r -- "${metadata%$'\n'}" || break
    sleep 3
  done
  kill "$cava_pid" 2>/dev/null
}

# Turns one CAVA frame ("v1;v2;...;") into ARTIFACTDOG_EQUALIZER_FRAME rows.
artifactdog_equalizer_render_frame() {
  local frame="$1"
  local value level previous peak=0 row column line glyph
  local -a values heights

  values=("${(@s/;/)frame}")
  for value in "${values[@]}"; do
    [[ "$value" == <-> ]] || continue
    (( value > peak )) && peak=$value
  done

  for (( column = 1; column <= ARTIFACTDOG_EQUALIZER_BARS; column++ )); do
    value="${values[$column]:-0}"
    [[ "$value" == <-> ]] || value=0
    if (( peak < 10 || value * 100 <= peak * 20 )); then
      level=0
    else
      level=$(( (value * 100 - peak * 20) * 24 / (peak * 80) ))
      (( level > 24 )) && level=24
    fi
    # Fast attack, eased decay.
    previous="${ARTIFACTDOG_EQUALIZER_LEVELS[$column]:-0}"
    if (( level < previous )); then
      level=$(( (previous * 3 + level) / 4 ))
    fi
    ARTIFACTDOG_EQUALIZER_LEVELS[$column]=$level
    heights[$column]=$level
  done

  ARTIFACTDOG_EQUALIZER_FRAME=()
  for (( row = ARTIFACTDOG_EQUALIZER_ROWS; row >= 1; row-- )); do
    line="${ARTIFACTDOG_EQUALIZER_INDENT}"
    for (( column = 1; column <= ARTIFACTDOG_EQUALIZER_BARS; column++ )); do
      level="${heights[$column]:-0}"
      if (( level >= row * 8 )); then
        glyph='█'
      elif (( level > (row - 1) * 8 )); then
        glyph="${ARTIFACTDOG_EQUALIZER_GLYPHS[$((level - (row - 1) * 8 + 1))]}"
      else
        glyph=' '
      fi
      line+="${glyph}${glyph} "
    done
    ARTIFACTDOG_EQUALIZER_FRAME+=("${line} ")
  done
}

# Asks the terminal for the cursor row (CSI 6n) and stores it in
# ARTIFACTDOG_EQUALIZER_CURSOR_ROW. Keys typed while waiting for the answer are
# handed back to the line editor (or the next prompt) instead of being lost.
artifactdog_equalizer_query_row() {
  local mode="$1" answer='' char tail leftover saved_tty=''

  ARTIFACTDOG_EQUALIZER_CURSOR_ROW=0
  # Outside zle the terminal is still in cooked mode: switch echo off before
  # asking, or a fast reply is echoed onto the screen.
  if [[ "$mode" != zle ]]; then
    saved_tty="$(stty -g 2>/dev/null)" || return 1
    stty -echo -icanon 2>/dev/null || return 1
  fi
  print -rn -- $'\e[6n' 2>/dev/null
  while read -rs -k 1 -t 1 char; do
    answer+="$char"
    [[ "$answer" == *$'\e['<->';'<->R ]] && break
  done
  [[ -n "$saved_tty" ]] && stty "$saved_tty" 2>/dev/null

  if [[ "$answer" == *$'\e['<->';'<->R ]]; then
    tail="${answer##*$'\e['}"
    leftover="${answer%$'\e['*}"
    ARTIFACTDOG_EQUALIZER_CURSOR_ROW="${tail%%;*}"
  else
    leftover="$answer"
  fi

  if [[ -n "$leftover" ]]; then
    if [[ "$mode" == zle ]]; then
      zle -U -- "$leftover"
    else
      print -rz -- "${leftover//[[:cntrl:]]/}"
    fi
  fi
  (( ARTIFACTDOG_EQUALIZER_CURSOR_ROW > 0 ))
}

# Index of the screen line (0 = first prompt line) on which TEXT ends when
# zle draws it right after the prompt. Gives the cursor's line for the text
# before the cursor, and the edit area's last line for the whole buffer.
artifactdog_equalizer_text_lines() {
  emulate -L zsh
  setopt extendedglob
  local prompt_text="${(%)PS1}" text segment
  local -a segments
  local -i lines=0 width

  prompt_text="${prompt_text//$'\e'\[[0-9;?]#[[:alpha:]]/}"
  segments=("${(@ps:\n:)prompt_text}")
  (( lines += ${#segments} - 1 ))
  text="${segments[-1]}$1"
  segments=("${(@ps:\n:)text}")
  for segment in "${(@)segments[1,-2]}"; do
    width=${(m)#segment}
    (( lines += width > 0 ? (width + COLUMNS - 1) / COLUMNS : 1 ))
  done
  segment="${segments[-1]}"
  width=${(m)#segment}
  REPLY=$(( lines + width / COLUMNS ))
}

# Called from zle hooks with the text before the cursor as it is currently on
# screen. Succeeds only if the bars are provably still where they were drawn.
artifactdog_equalizer_verify() {
  local -i start valid=0

  (( COLUMNS == ARTIFACTDOG_EQUALIZER_ANCHOR_COLUMNS )) || return 1
  (( LINES == ARTIFACTDOG_EQUALIZER_ANCHOR_LINES )) || return 1
  artifactdog_equalizer_query_row zle || return 1
  artifactdog_equalizer_text_lines "$1"
  start=$(( ARTIFACTDOG_EQUALIZER_CURSOR_ROW - REPLY ))

  if (( ARTIFACTDOG_EQUALIZER_NEW_PROMPT )); then
    # A new prompt below the old one, and not on the last row, means the
    # output in between never scrolled the screen. The first prompt may also
    # start exactly on the row recorded right after the banner.
    if (( start > ARTIFACTDOG_EQUALIZER_PROMPT_ROW && start < LINES )); then
      valid=1
    elif (( ARTIFACTDOG_EQUALIZER_FIRST_PROMPT &&
            start == ARTIFACTDOG_EQUALIZER_PROMPT_ROW )); then
      valid=1
    fi
  else
    (( start == ARTIFACTDOG_EQUALIZER_PROMPT_ROW )) && valid=1
  fi
  (( valid )) || return 1

  ARTIFACTDOG_EQUALIZER_PROMPT_ROW=$start
  ARTIFACTDOG_EQUALIZER_NEW_PROMPT=0
  ARTIFACTDOG_EQUALIZER_FIRST_PROMPT=0
  ARTIFACTDOG_EQUALIZER_LAST_CHECK=$EPOCHREALTIME
}

artifactdog_equalizer_paint() {
  local output=$'\e7' line
  local -i row=$ARTIFACTDOG_EQUALIZER_TOP

  for line in "${ARTIFACTDOG_EQUALIZER_FRAME[@]}"; do
    output+=$'\e['"${row};1H${line}"
    (( row++ ))
  done
  output+=$'\e['"${row};1H${ARTIFACTDOG_EQUALIZER_NOW_PLAYING}"$'\e[K\e8'
  print -rn -- "$output"
}

# zle -F handler (a plain function, not a widget, so LASTWIDGET, kill-ring
# appends, yank-pop and menu completion are untouched): drain every queued
# CAVA frame and paint only the newest one.
artifactdog_equalizer_on_frame() {
  emulate -L zsh
  local fd="$1" frame latest='' snapshot

  if [[ -n "${2:-}" ]]; then
    artifactdog_equalizer_stop
    return 0
  fi
  while IFS= read -r -t 0 -u "$fd" frame; do
    latest="$frame"
  done
  [[ -n "$latest" ]] || return 0

  artifactdog_equalizer_render_frame "$latest"
  (( ARTIFACTDOG_EQUALIZER_PAUSED )) && return 0
  if (( COLUMNS != ARTIFACTDOG_EQUALIZER_ANCHOR_COLUMNS ||
        LINES != ARTIFACTDOG_EQUALIZER_ANCHOR_LINES )); then
    artifactdog_equalizer_stop
    return 0
  fi
  snapshot="${(pj:\n:)ARTIFACTDOG_EQUALIZER_FRAME}"$'\n'"$ARTIFACTDOG_EQUALIZER_NOW_PLAYING"
  [[ "$snapshot" == "$ARTIFACTDOG_EQUALIZER_PAINTED" ]] && return 0
  artifactdog_equalizer_paint
  ARTIFACTDOG_EQUALIZER_PAINTED="$snapshot"
  return 0
}

# zle -F handler: pick up the newest "artist<TAB>title" line.
artifactdog_equalizer_on_metadata() {
  emulate -L zsh
  local fd="$1" metadata latest='' got=0

  if [[ -n "${2:-}" ]]; then
    zle -F "$fd" 2>/dev/null
    return 0
  fi
  while IFS= read -r -t 0 -u "$fd" metadata; do
    latest="$metadata"
    got=1
  done
  (( got )) && artifactdog_equalizer_apply_now_playing "$latest"
  return 0
}

# Widgets whose redraw stays inside the edit area, so the screen can only
# scroll if the buffer itself outgrows the bottom row (checked before the
# redraw). After any other widget (completion lists, searches, messages,
# clear-screen, ...) painting pauses until the next hook proves the screen
# did not move.
typeset -gA ARTIFACTDOG_EQUALIZER_SAFE_WIDGETS=()
() {
  local widget
  for widget in \
    self-insert self-insert-unmeta magic-space quoted-insert bracketed-paste \
    backward-delete-char delete-char forward-char backward-char \
    forward-word backward-word emacs-forward-word emacs-backward-word \
    beginning-of-line end-of-line kill-line backward-kill-line \
    kill-whole-line kill-word backward-kill-word kill-region kill-buffer \
    copy-region-as-kill yank yank-pop undo redo transpose-chars \
    transpose-words capitalize-word up-case-word down-case-word \
    set-mark-command exchange-point-and-mark \
    up-line-or-history down-line-or-history up-history down-history \
    up-line-or-search down-line-or-search \
    up-line-or-beginning-search down-line-or-beginning-search \
    history-search-backward history-search-forward \
    history-beginning-search-backward history-beginning-search-forward \
    beginning-of-history end-of-history \
    beginning-of-buffer-or-history end-of-buffer-or-history \
    accept-line send-break
  do
    ARTIFACTDOG_EQUALIZER_SAFE_WIDGETS[$widget]=1
  done
}

# zle-line-init hook: the prompt has just been drawn.
artifactdog_equalizer_line_init() {
  emulate -L zsh
  (( ARTIFACTDOG_EQUALIZER_ACTIVE )) || return 0
  if ! artifactdog_equalizer_verify "${PREDISPLAY}${LBUFFER}"; then
    artifactdog_equalizer_stop
    return 0
  fi
  ARTIFACTDOG_EQUALIZER_SHOWN="${PREDISPLAY}${LBUFFER}"
  ARTIFACTDOG_EQUALIZER_PAUSED=0
}

# zle-line-pre-redraw hook: runs after every widget, before zle redraws.
artifactdog_equalizer_pre_redraw() {
  emulate -L zsh
  (( ARTIFACTDOG_EQUALIZER_ACTIVE )) || return 0

  # If the previous redraw was not predictable, or a while has passed (to
  # catch background job output), check what is on screen right now.
  if (( ARTIFACTDOG_EQUALIZER_PAUSED ||
        EPOCHREALTIME - ARTIFACTDOG_EQUALIZER_LAST_CHECK >= 2.0 )); then
    if ! artifactdog_equalizer_verify "$ARTIFACTDOG_EQUALIZER_SHOWN"; then
      artifactdog_equalizer_stop
      return 0
    fi
  fi

  # Then judge the redraw that is about to happen.
  if (( ${+ARTIFACTDOG_EQUALIZER_SAFE_WIDGETS[$LASTWIDGET]} )); then
    artifactdog_equalizer_text_lines "${PREDISPLAY}${BUFFER}${POSTDISPLAY}"
    if (( ARTIFACTDOG_EQUALIZER_PROMPT_ROW + REPLY > LINES )); then
      artifactdog_equalizer_stop
      return 0
    fi
    ARTIFACTDOG_EQUALIZER_PAUSED=0
  else
    ARTIFACTDOG_EQUALIZER_PAUSED=1
  fi
  ARTIFACTDOG_EQUALIZER_SHOWN="${PREDISPLAY}${LBUFFER}"
}

artifactdog_equalizer_precmd() {
  emulate -L zsh
  ARTIFACTDOG_EQUALIZER_NEW_PROMPT=1
  ARTIFACTDOG_EQUALIZER_PAUSED=1
}

artifactdog_equalizer_stop() {
  emulate -L zsh
  local fd

  for fd in "$ARTIFACTDOG_EQUALIZER_FD" "$ARTIFACTDOG_EQUALIZER_META_FD"; do
    [[ -n "$fd" ]] || continue
    zle -F "$fd" 2>/dev/null
    exec {fd}<&- 2>/dev/null
  done
  [[ -n "$ARTIFACTDOG_EQUALIZER_META_PID" ]] && kill "$ARTIFACTDOG_EQUALIZER_META_PID" 2>/dev/null
  [[ -n "$ARTIFACTDOG_EQUALIZER_PID" ]] && kill "$ARTIFACTDOG_EQUALIZER_PID" 2>/dev/null
  if [[ -n "$ARTIFACTDOG_EQUALIZER_DIR" && -d "$ARTIFACTDOG_EQUALIZER_DIR" ]]; then
    rm -rf -- "$ARTIFACTDOG_EQUALIZER_DIR"
  fi
  ARTIFACTDOG_EQUALIZER_FD=''
  ARTIFACTDOG_EQUALIZER_META_FD=''
  ARTIFACTDOG_EQUALIZER_PID=''
  ARTIFACTDOG_EQUALIZER_META_PID=''
  ARTIFACTDOG_EQUALIZER_DIR=''
  ARTIFACTDOG_EQUALIZER_ACTIVE=0

  add-zsh-hook -d precmd artifactdog_equalizer_precmd
  add-zsh-hook -d zshexit artifactdog_equalizer_stop
  add-zle-hook-widget -d line-init artifactdog_equalizer_line_init 2>/dev/null
  add-zle-hook-widget -d line-pre-redraw artifactdog_equalizer_pre_redraw 2>/dev/null
  return 0
}

artifactdog_equalizer_start() {
  emulate -L zsh
  local frames_fifo metadata_fifo
  local -i width

  # Lay out the static part: empty bar rows, track line, spacer, then find
  # out which row the prompt will start on.
  artifactdog_equalizer_width
  width=$REPLY
  artifactdog_equalizer_render_frame ''
  if (( COLUMNS > width )); then
    print -rl -- "${ARTIFACTDOG_EQUALIZER_FRAME[@]}"
  fi
  print -r -- "$ARTIFACTDOG_EQUALIZER_NOW_PLAYING"
  print -r -- ''
  (( COLUMNS > width )) || return 1

  artifactdog_equalizer_query_row prompt || return 1
  ARTIFACTDOG_EQUALIZER_PROMPT_ROW=$ARTIFACTDOG_EQUALIZER_CURSOR_ROW
  ARTIFACTDOG_EQUALIZER_TOP=$(( ARTIFACTDOG_EQUALIZER_PROMPT_ROW - ARTIFACTDOG_EQUALIZER_ROWS - 2 ))
  (( ARTIFACTDOG_EQUALIZER_TOP >= 1 )) || return 1
  ARTIFACTDOG_EQUALIZER_ANCHOR_COLUMNS=$COLUMNS
  ARTIFACTDOG_EQUALIZER_ANCHOR_LINES=$LINES

  ARTIFACTDOG_EQUALIZER_DIR="$(mktemp -d "${TMPDIR:-/tmp}/artifactdog-cava.XXXXXX")" || return 1
  frames_fifo="$ARTIFACTDOG_EQUALIZER_DIR/frames"
  metadata_fifo="$ARTIFACTDOG_EQUALIZER_DIR/metadata"
  mkfifo "$frames_fifo" "$metadata_fifo" || return 1

  cava -p "$HOME/.config/cava/config" >"$frames_fifo" \
    2>"$ARTIFACTDOG_EQUALIZER_DIR/cava.log" </dev/null &!
  ARTIFACTDOG_EQUALIZER_PID=$!
  exec {ARTIFACTDOG_EQUALIZER_FD}<>"$frames_fifo" || return 1

  artifactdog_equalizer_metadata_worker $$ "$ARTIFACTDOG_EQUALIZER_PID" \
    >"$metadata_fifo" 2>/dev/null </dev/null &!
  ARTIFACTDOG_EQUALIZER_META_PID=$!
  exec {ARTIFACTDOG_EQUALIZER_META_FD}<>"$metadata_fifo" || return 1
  rm -f -- "$frames_fifo" "$metadata_fifo"

  zle -F "$ARTIFACTDOG_EQUALIZER_FD" artifactdog_equalizer_on_frame
  zle -F "$ARTIFACTDOG_EQUALIZER_META_FD" artifactdog_equalizer_on_metadata
  add-zle-hook-widget line-init artifactdog_equalizer_line_init
  add-zle-hook-widget line-pre-redraw artifactdog_equalizer_pre_redraw
  add-zsh-hook precmd artifactdog_equalizer_precmd
  add-zsh-hook zshexit artifactdog_equalizer_stop
  ARTIFACTDOG_EQUALIZER_ACTIVE=1
}

if ! artifactdog_equalizer_start; then
  artifactdog_equalizer_stop
fi
