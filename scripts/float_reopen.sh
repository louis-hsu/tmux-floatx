#!/usr/bin/env bash

CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$CURRENT_DIR/utils.sh"

# Phase 2: called from run-shell -b, outside the launcher popup context
if [ "$1" = "--open" ]; then
    floatx_log "[reopen/p2] pane=$(env_val FLOATX_PANE) position=$(env_val FLOATX_POSITION)"
    set_move_bindings
    open_popup
    exit 0
fi

# Phase 1: runs inside the launcher popup (chained after cmd exits)
session="$(env_val FLOATX_SESSION)"
[ -z "$session" ] && session="$DEFAULT_SESSION"

floatx_log "[reopen/p1] session=$session pane=$(env_val FLOATX_PANE)"

# Recreate float session if it was killed while the launcher was open
if ! tmux has-session -t "$session" 2>/dev/null; then
    floatx_log "[reopen/p1] session missing — recreating"
    tmux new-session -d -s "$session"
    tmux set-option -t "$session" status off
    tmux setenv -g FLOATX_POSITION "center"
fi

# Schedule phase 2 via run-shell -b so it executes outside this popup's context,
# avoiding nested-popup restrictions. The sleep ensures the launcher popup is
# fully closed before the float window opens.
tmux run-shell -b "sleep 0.1; '$CURRENT_DIR/float_reopen.sh' --open"
