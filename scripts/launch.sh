#!/usr/bin/env bash

CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$CURRENT_DIR/utils.sh"

index="$1"
cmd="$(env_val "FLOATX_LAUNCH_${index}_CMD")"
[ -z "$cmd" ] && exit 1

session="$(env_val FLOATX_SESSION)"
[ -z "$session" ] && session="$DEFAULT_SESSION"

current_session="$(tmux display-message -p '#{session_name}')"
cwd="$(tmux display-message -p '#{pane_current_path}')"

if [ "$current_session" = "$session" ]; then
    # Called from inside the float session:
    # - Use stored original pane as popup target (not the float session's pane)
    # - FLOATX_WIN_W/H are already correct from toggle.sh — don't overwrite
    # - Dismiss float first, reopen it after launcher exits
    pane="$(env_val FLOATX_PANE)"
    floatx_log "[launch] inside-float | index=$index cmd=[$cmd] pane=$pane cwd=$cwd"
    unset_move_bindings
    tmux detach-client
    open_launcher_popup "$cmd" "$cwd" "$pane" "$CURRENT_DIR/float_reopen.sh"
else
    # Called from outside the float session — use current pane as target
    pane="$(tmux display-message -p '#{pane_id}')"
    floatx_log "[launch] outside-float | index=$index cmd=[$cmd] pane=$pane cwd=$cwd"
    open_launcher_popup "$cmd" "$cwd" "$pane"
fi
