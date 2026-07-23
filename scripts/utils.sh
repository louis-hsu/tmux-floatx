#!/usr/bin/env bash

DEFAULT_SESSION="floatx"
LOG_FILE="/tmp/floatx_debug.log"

floatx_log() {
    [ "$(env_val FLOATX_DEBUG)" = "on" ] || return 0
    echo "$(date '+%H:%M:%S') $*" >> "$LOG_FILE"
}

# Strip surrounding single or double quotes from a string
strip_quotes() {
    local s="$1"
    s="${s#\"}" ; s="${s%\"}"
    s="${s#\'}" ; s="${s%\'}"
    echo "$s"
}

# Read a tmux option with a fallback default
tmux_opt() {
    local val
    val="$(tmux show-option -gqv "$1")"
    strip_quotes "${val:-$2}"
}

# Read a tmux option then immediately unset it so stale values from a previous
# tmux.conf don't survive a reload where the option was removed.
tmux_opt_consume() {
    local val
    val="$(tmux show-option -gqv "$1")"
    tmux set-option -gqu "$1" 2>/dev/null
    strip_quotes "${val:-$2}"
}

# Read a value from tmux global environment
env_val() {
    local val
    val="$(tmux showenv -g "$1" 2>/dev/null | cut -d'=' -f2-)"
    strip_quotes "$val"
}

# Parse a key from a "k=v,k=v" string
# Usage: parse_kv "w=80%,h=80%" "w"  →  "80%"
parse_kv() {
    echo "$1" | tr ',' '\n' | grep "^$2=" | cut -d'=' -f2-
}

# Convert a percentage string (e.g. "50%" or "0") to an absolute column/row count
pct_to_abs() {
    local num="${1//%/}"  # strip % if present
    echo $(( $2 * num / 100 ))
}

# Bind move keys as root-table (no prefix) — only called when inside float session
set_move_bindings() {
    local script_dir bind_right bind_left bind_resume
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    bind_right="$(env_val FLOATX_BIND_RIGHT)"
    bind_left="$(env_val FLOATX_BIND_LEFT)"
    bind_resume="$(env_val FLOATX_BIND_RESUME)"
    tmux bind -n "$bind_right"  run-shell "$script_dir/position.sh right"
    tmux bind -n "$bind_left"   run-shell "$script_dir/position.sh left"
    tmux bind -n "$bind_resume" run-shell "$script_dir/position.sh center"
}

# Remove move key bindings — called when leaving float session
unset_move_bindings() {
    local bind_right bind_left bind_resume
    bind_right="$(env_val FLOATX_BIND_RIGHT)"
    bind_left="$(env_val FLOATX_BIND_LEFT)"
    bind_resume="$(env_val FLOATX_BIND_RESUME)"
    tmux unbind -n "$bind_right"  2>/dev/null || true
    tmux unbind -n "$bind_left"   2>/dev/null || true
    tmux unbind -n "$bind_resume" 2>/dev/null || true
}

# Open the float popup at the current FLOATX_POSITION (center|left|right).
# Terminal dimensions are read from FLOATX_WIN_W/H env vars, which must be
# set by the caller before any detach-client call.
open_popup() {
    local session origin pane position size w h win_w half_w w_abs x_abs target_info title border_color

    session="$(env_val FLOATX_SESSION)"
    [ -z "$session" ] && session="$DEFAULT_SESSION"

    local base_title bind_right bind_left bind_resume
    base_title="$(env_val FLOATX_TITLE)"
    [ -z "$base_title" ] && base_title="Floatx"
    bind_right="$(env_val FLOATX_BIND_RIGHT)"
    bind_left="$(env_val FLOATX_BIND_LEFT)"
    bind_resume="$(env_val FLOATX_BIND_RESUME)"
    title="$base_title | [$bind_right] move right | [$bind_left] move left | [$bind_resume] resume"

    border_color="$(env_val FLOATX_BORDER_COLOR)"
    [ -z "$border_color" ] && border_color="magenta"

    origin="$(env_val FLOATX_ORIGIN)"
    # Use stored pane ID for precise client targeting — session name may resolve
    # to any attached client (wrong size), but pane ID is unambiguous.
    pane="$(env_val FLOATX_PANE)"
    [ -z "$pane" ] && pane="$origin"

    position="$(env_val FLOATX_POSITION)"
    [ -z "$position" ] && position="center"

    # Log which client tmux actually resolves for our target
    target_info="$(tmux display-message -t "$pane" -p '#{client_name} #{client_width}x#{client_height}' 2>/dev/null)"

    case "$position" in
        center)
            size="$(env_val FLOATX_SIZE)"
            w="$(parse_kv "$size" "w")"
            h="$(parse_kv "$size" "h")"
            floatx_log "[popup] position=center | origin=$origin pane=$pane target=[$target_info] src_w=$(env_val FLOATX_WIN_W) src_h=$(env_val FLOATX_WIN_H) | cfg @floatx-size=$size | float w=$w h=$h x=C y=C"
            # -t pane pins the popup to the exact client captured at toggle time.
            # -x C -y C delegates centering to tmux; w/h accept % strings directly.
            tmux popup -t "$pane" -x C -y C -w "$w" -h "$h" \
                -T "$title" -S "fg=$border_color" \
                -b rounded -E "tmux attach-session -t '$session'"
            ;;
        left)
            # x: centre popup within left half (absolute); y/h: let tmux handle via C/%
            size="$(env_val FLOATX_LEFT_SIZE)"
            w="$(parse_kv "$size" "w")"
            h="$(parse_kv "$size" "h")"
            win_w="$(env_val FLOATX_WIN_W)"
            half_w=$(( win_w / 2 ))
            w_abs=$(pct_to_abs "$w" "$half_w")
            x_abs=$(( (half_w - w_abs) / 2 ))
            floatx_log "[popup] position=left  | origin=$origin pane=$pane target=[$target_info] src_w=$win_w src_h=$(env_val FLOATX_WIN_H) | cfg @floatx-left-size=$size | float w=$w_abs h=$h x=$x_abs y=C"
            tmux popup -t "$pane" -x "$x_abs" -y C -w "$w_abs" -h "$h" \
                -T "$title" -S "fg=$border_color" \
                -b rounded -E "tmux attach-session -t '$session'"
            ;;
        right)
            # x: centre popup within right half (absolute); y/h: let tmux handle via C/%
            size="$(env_val FLOATX_RIGHT_SIZE)"
            w="$(parse_kv "$size" "w")"
            h="$(parse_kv "$size" "h")"
            win_w="$(env_val FLOATX_WIN_W)"
            half_w=$(( win_w / 2 ))
            w_abs=$(pct_to_abs "$w" "$half_w")
            x_abs=$(( half_w + (half_w - w_abs) / 2 ))
            floatx_log "[popup] position=right | origin=$origin pane=$pane target=[$target_info] src_w=$win_w src_h=$(env_val FLOATX_WIN_H) | cfg @floatx-right-size=$size | float w=$w_abs h=$h x=$x_abs y=C"
            tmux popup -t "$pane" -x "$x_abs" -y C -w "$w_abs" -h "$h" \
                -T "$title" -S "fg=$border_color" \
                -b rounded -E "tmux attach-session -t '$session'"
            ;;
    esac
}

# Open an ephemeral popup running cmd directly (no session attachment).
# Always centered, working directory set to cwd, styled with floatx theme.
# Usage: open_launcher_popup <cmd> <cwd> <pane> [post_cmd]
open_launcher_popup() {
    local cmd="$1"
    local cwd="$2"
    local pane="$3"
    local post_cmd="$4"   # optional: run after cmd exits (used to reopen float)

    local size w h base_title title border_color

    size="$(env_val FLOATX_SIZE)"
    w="$(parse_kv "$size" "w")"
    h="$(parse_kv "$size" "h")"

    base_title="$(env_val FLOATX_TITLE)"
    [ -z "$base_title" ] && base_title="Floatx"
    title="$base_title | $cmd"

    border_color="$(env_val FLOATX_BORDER_COLOR)"
    [ -z "$border_color" ] && border_color="magenta"

    # Run cmd via interactive shell so aliases/functions (e.g. from .zshrc) resolve
    local shell="${SHELL:-/bin/bash}"
    local full_cmd
    full_cmd="$(printf '%q' "$shell") -ic $(printf '%q' "$cmd")"
    [ -n "$post_cmd" ] && full_cmd="$full_cmd; '$post_cmd'"

    floatx_log "[launcher] cmd=[$cmd] post_cmd=[$post_cmd] full_cmd=[$full_cmd] pane=$pane cwd=$cwd w=$w h=$h"

    local popup_args=(-t "$pane" -x C -y C -w "$w" -h "$h" -T "$title" -S "fg=$border_color" -b rounded)
    [ -n "$cwd" ] && popup_args+=(-d "$cwd")
    popup_args+=(-E "$full_cmd")
    tmux popup "${popup_args[@]}"
}
