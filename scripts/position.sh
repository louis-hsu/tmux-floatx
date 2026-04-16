#!/usr/bin/env bash

CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$CURRENT_DIR/utils.sh"

session="$(env_val FLOATX_SESSION)"
[ -z "$session" ] && session="$DEFAULT_SESSION"

# Guard: only run if we're actually inside the float session.
# If the move keys fire outside it (stale bindings), clean up and exit.
if [ "$(tmux display-message -p '#{session_name}')" != "$session" ]; then
    unset_move_bindings
    exit 0
fi

new_pos="$1"

# Pressing the same direction twice toggles back to center
current="$(env_val FLOATX_POSITION)"
[ "$current" = "$new_pos" ] && new_pos="center"

# Read current terminal size from the stored TTY device path via stty.
# This bypasses tmux entirely — stty reads TIOCGWINSZ from the OS, which always
# reflects the true terminal dimensions regardless of any popup overlay.
tty_path="$(env_val FLOATX_CLIENT_TTY)"
if [ -n "$tty_path" ] && [ -e "$tty_path" ]; then
    dims="$(stty size < "$tty_path" 2>/dev/null)"  # "rows cols"
    [ -n "$dims" ] && tmux setenv -g FLOATX_WIN_H "${dims%% *}" \
                   && tmux setenv -g FLOATX_WIN_W "${dims##* }"
fi

tmux setenv -g FLOATX_POSITION "$new_pos"
tmux detach-client
open_popup
