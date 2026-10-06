#!/usr/bin/env bash

CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$CURRENT_DIR/utils.sh"

session="$(env_val FLOATX_SESSION)"
[ -z "$session" ] && session="$DEFAULT_SESSION"

# Guard: only run inside the float session (binding already filters on this)
if [ "$(tmux display-message -p '#{session_name}')" != "$session" ]; then
    exit 0
fi

# Capture the float's active pane before any detach — afterwards
# display-message would resolve a different client.
fp="$(tmux display-message -p '#{pane_id}')"
popup_client="$(tmux display-message -p '#{client_name}')"

# Target origin by session ID so a renamed origin session still resolves
origin="$(env_val FLOATX_ORIGIN_ID)"
[ -z "$origin" ] && origin="$(env_val FLOATX_ORIGIN)"

if [ -z "$origin" ] || ! tmux has-session -t "$origin" 2>/dev/null; then
    floatx_log "[dock] origin missing | fp=$fp origin=$origin"
    tmux display-message "floatx: origin session not found — cannot dock"
    exit 0
fi

unset_move_bindings

# Detach the popup client explicitly and before break-pane. If fp is the
# float's last pane, break-pane destroys the float session and the popup client
# with it; a bare detach-client afterwards would fall back to tmux's "best"
# client — the user's outer client — and detach their main session.
tmux detach-client -t "$popup_client" 2>/dev/null || true

# break-pane with a session-only target creates a new window at the next free
# index in origin and moves fp into it.
new_win="$(tmux break-pane -d -s "$fp" -t "$origin:" -P -F '#{window_id}')"
floatx_log "[dock] fp=$fp client=$popup_client origin=$origin new_win=$new_win"

[ -n "$new_win" ] && tmux select-window -t "$new_win"
