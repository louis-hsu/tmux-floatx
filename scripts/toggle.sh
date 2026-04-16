#!/usr/bin/env bash

CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$CURRENT_DIR/utils.sh"

session="$(env_val FLOATX_SESSION)"
[ -z "$session" ] && session="$DEFAULT_SESSION"

if [ "$(tmux display-message -p '#{session_name}')" = "$session" ]; then
    # Currently inside the float session — hide it
    unset_move_bindings
    tmux detach-client
else
    # Outside the float session — capture dimensions now, before any detach
    tmux setenv -g FLOATX_ORIGIN     "$(tmux display-message -p '#{session_name}')"
    tmux setenv -g FLOATX_PANE       "$(tmux display-message -p '#{pane_id}')"
    tmux setenv -g FLOATX_CLIENT     "$(tmux display-message -p '#{client_name}')"
    tmux setenv -g FLOATX_CLIENT_TTY "$(tmux display-message -p '#{client_tty}')"
    tmux setenv -g FLOATX_WIN_W      "$(tmux display-message -p '#{client_width}')"
    tmux setenv -g FLOATX_WIN_H      "$(tmux display-message -p '#{client_height}')"

    if ! tmux has-session -t "$session" 2>/dev/null; then
        tmux new-session -d -s "$session" \
            -c "$(tmux display-message -p '#{pane_current_path}')"
        tmux set-option -t "$session" status off
        # Fresh session — reset position so popup opens at center, not a stale position
        tmux setenv -g FLOATX_POSITION "center"
    fi

    set_move_bindings
    open_popup
fi
