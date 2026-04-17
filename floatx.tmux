#!/usr/bin/env bash

CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$CURRENT_DIR/scripts/utils.sh"

# tmux_opt_consume reads each option then immediately unsets it.
# This prevents stale values from surviving a config reload where the option
# was removed from tmux.conf — on the next reload only options still present
# in tmux.conf will be re-set before this script runs.
#
# NOTE: for config changes to take effect, this script must be re-run after
# sourcing tmux.conf. Add this line at the END of tmux.conf (after all
# @floatx-* options) for a single-reload workflow:
#   run-shell "bash /path/to/tmux-floatx/plugin.tmux"
# Convert a bare key name to a Ctrl+Key tmux binding name.
# Arrow keys must be capitalized in tmux: "right" → "C-Right", "up" → "C-Up".
# Regular letter keys stay lowercase:      "h"     → "C-h".
make_ctrl_key() {
    local key="$1"
    case "$key" in
        up|down|left|right)
            echo "C-$(echo "${key:0:1}" | tr '[:lower:]' '[:upper:]')${key:1}"
            ;;
        *)
            echo "C-$key"
            ;;
    esac
}

tmux setenv -g FLOATX_SIZE        "$(tmux_opt_consume '@floatx-size'        'w=80%,h=80%')"
tmux setenv -g FLOATX_RIGHT_SIZE  "$(tmux_opt_consume '@floatx-right-size'  'w=85%,h=90%')"
tmux setenv -g FLOATX_LEFT_SIZE   "$(tmux_opt_consume '@floatx-left-size'   'w=85%,h=90%')"
tmux setenv -g FLOATX_SESSION     "$(tmux_opt_consume '@floatx-session-name' 'floatx')"
tmux setenv -g FLOATX_TITLE       "$(tmux_opt_consume '@floatx-title'        'MyFloatx')"
tmux setenv -g FLOATX_BORDER_COLOR "$(tmux_opt_consume '@floatx-border-color' 'colour214')"
tmux setenv -g FLOATX_DEBUG       "$(tmux_opt_consume '@floatx-debug'        'off')"
tmux setenv -g FLOATX_POSITION    "center"

# Unbind previous keys before rebinding — prevents stale keys from lingering
# when the user changes a binding and reloads.
_prev_toggle="$(env_val FLOATX_BIND_TOGGLE)"
_prev_right="$(env_val FLOATX_BIND_RIGHT)"
_prev_left="$(env_val FLOATX_BIND_LEFT)"
_prev_resume="$(env_val FLOATX_BIND_RESUME)"
[ -n "$_prev_toggle" ] && tmux unbind-key        "$_prev_toggle" 2>/dev/null || true
[ -n "$_prev_right"  ] && tmux unbind-key -n     "$_prev_right"  2>/dev/null || true
[ -n "$_prev_left"   ] && tmux unbind-key -n     "$_prev_left"   2>/dev/null || true
[ -n "$_prev_resume" ] && tmux unbind-key -n     "$_prev_resume" 2>/dev/null || true

_toggle="$(tmux_opt_consume '@floatx-bind-toggle' 'p')"
_right="$(make_ctrl_key "$(tmux_opt_consume '@floatx-bind-right'  'right')")"
_left="$(make_ctrl_key  "$(tmux_opt_consume '@floatx-bind-left'   'left')")"
_resume="$(make_ctrl_key "$(tmux_opt_consume '@floatx-bind-resume' 'up')")"

tmux setenv -g FLOATX_BIND_TOGGLE "$_toggle"
tmux setenv -g FLOATX_BIND_RIGHT  "$_right"
tmux setenv -g FLOATX_BIND_LEFT   "$_left"
tmux setenv -g FLOATX_BIND_RESUME "$_resume"

[ "$(env_val FLOATX_DEBUG)" = "on" ] && \
    echo "=== floatx loaded $(date '+%Y-%m-%d %H:%M:%S') ===" > /tmp/floatx_debug.log

# Toggle key (requires prefix, e.g. <prefix>+p)
tmux bind-key "$_toggle" run-shell "$CURRENT_DIR/scripts/toggle.sh"
