#!/usr/bin/env bash
# Tests for the floatx launcher reopen flow.
# Run: bash tests/test_launcher_reopen.sh
# Requirements: tmux server running (any session).

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPTS="$REPO/scripts"
LOG_FILE="/tmp/floatx_debug.log"
PASS=0; FAIL=0

# ── helpers ──────────────────────────────────────────────────────────────────

pass() { echo "  PASS  $1"; PASS=$((PASS+1)); }
fail() { echo "  FAIL  $1"; FAIL=$((FAIL+1)); }

assert_log() {
    local desc="$1" pattern="$2"
    if grep -q "$pattern" "$LOG_FILE" 2>/dev/null; then
        pass "$desc"
    else
        fail "$desc  [pattern not found: $pattern]"
        echo "        --- log tail ---"
        tail -8 "$LOG_FILE" 2>/dev/null | sed 's/^/        /'
    fi
}

assert_not_log() {
    local desc="$1" pattern="$2"
    if ! grep -q "$pattern" "$LOG_FILE" 2>/dev/null; then
        pass "$desc"
    else
        fail "$desc  [unexpected pattern found: $pattern]"
    fi
}

clear_log() { > "$LOG_FILE"; }

# ── prerequisite ─────────────────────────────────────────────────────────────

if ! tmux info &>/dev/null; then
    echo "ERROR: no tmux server running. Start a tmux session first."
    exit 1
fi

CURRENT_PANE="$(tmux display-message -p '#{pane_id}')"
export TEST_SESSION="floatx_test_$$"   # exported so child bash processes inherit it

echo "=== tmux-floatx launcher reopen tests ==="
echo "    scripts dir : $SCRIPTS"
echo "    log file    : $LOG_FILE"
echo "    test session: $TEST_SESSION"
echo "    current pane: $CURRENT_PANE"
echo ""

# Set up shared FLOATX_* env vars used by all tests
tmux new-session -d -s "$TEST_SESSION"
tmux setenv -g FLOATX_DEBUG        "on"          # enable logging for all tests
tmux setenv -g FLOATX_SESSION      "$TEST_SESSION"
tmux setenv -g FLOATX_PANE         "$CURRENT_PANE"
tmux setenv -g FLOATX_POSITION     "center"
tmux setenv -g FLOATX_SIZE         "w=80%,h=80%"
tmux setenv -g FLOATX_TITLE        "TestFloat"
tmux setenv -g FLOATX_BORDER_COLOR "colour214"
tmux setenv -g FLOATX_BIND_RIGHT   "C-Right"
tmux setenv -g FLOATX_BIND_LEFT    "C-Left"
tmux setenv -g FLOATX_BIND_RESUME  "C-Up"
tmux setenv -g FLOATX_LAUNCH_1_CMD "echo launcher_test"

# ── T1: open_launcher_popup full_cmd construction ────────────────────────────
echo "T1: open_launcher_popup — full_cmd includes post_cmd when provided"
clear_log
(
    source "$SCRIPTS/utils.sh"
    # Allow showenv through to real tmux (needed for floatx_log and env_val).
    # Mock only tmux popup to prevent opening a real popup.
    tmux() {
        case "$1" in
            showenv) command tmux "$@" ;;
            popup)   floatx_log "[test] mock: tmux popup called" ;;
            *)       : ;;
        esac
    }
    export -f tmux
    open_launcher_popup "echo test" "/tmp" "$CURRENT_PANE" "/path/to/float_reopen.sh"
)
assert_log "full_cmd logged"          "\[launcher\] cmd=\[echo test\]"
assert_log "post_cmd in full_cmd"     "full_cmd=\[echo test; '/path/to/float_reopen.sh'\]"
assert_log "tmux popup mocked"        "\[test\] mock: tmux popup called"
echo ""

# ── T2: open_launcher_popup without post_cmd ─────────────────────────────────
echo "T2: open_launcher_popup — full_cmd equals cmd when no post_cmd"
clear_log
(
    source "$SCRIPTS/utils.sh"
    tmux() {
        case "$1" in
            showenv) command tmux "$@" ;;
            popup)   floatx_log "[test] mock: tmux popup called" ;;
            *)       : ;;
        esac
    }
    export -f tmux
    open_launcher_popup "echo test" "/tmp" "$CURRENT_PANE"
)
assert_log "cmd logged"               "\[launcher\] cmd=\[echo test\]"
assert_log "full_cmd equals cmd"      "post_cmd=\[\] full_cmd=\[echo test\]"
echo ""

# ── T3: launch.sh outside-float branch ───────────────────────────────────────
echo "T3: launch.sh — takes outside-float branch (current != float session)"
clear_log
(
    source "$SCRIPTS/utils.sh"
    tmux() {
        case "$*" in
            "display-message -p #{session_name}")    echo "main" ;;
            "display-message -p #{pane_current_path}") echo "/tmp" ;;
            "display-message -p #{pane_id}")         echo "$CURRENT_PANE" ;;
            showenv*)  command tmux "$@" ;;
            popup*)    floatx_log "[test] mock: tmux popup called" ;;
            *)         : ;;
        esac
    }
    export -f tmux
    bash "$SCRIPTS/launch.sh" 1
)
assert_log     "launch outside-float"   "\[launch\] outside-float"
assert_not_log "inside-float NOT taken" "\[launch\] inside-float"
echo ""

# ── T4: launch.sh inside-float branch ────────────────────────────────────────
echo "T4: launch.sh — takes inside-float branch (current == float session)"
clear_log
(
    source "$SCRIPTS/utils.sh"
    tmux() {
        case "$*" in
            "display-message -p #{session_name}")    echo "$TEST_SESSION" ;;
            "display-message -p #{pane_current_path}") echo "/tmp" ;;
            detach-client)  floatx_log "[test] mock: detach-client called" ;;
            showenv*)  command tmux "$@" ;;
            popup*)    floatx_log "[test] mock: tmux popup called" ;;
            *)         : ;;
        esac
    }
    export -f tmux
    bash "$SCRIPTS/launch.sh" 1
)
assert_log "launch inside-float"      "\[launch\] inside-float"
assert_log "detach-client called"     "\[test\] mock: detach-client called"
assert_log "post_cmd is float_reopen" "\[launcher\].*post_cmd=\[.*float_reopen"
echo ""

# ── T5: float_reopen.sh phase 1 (non-blocking run-shell -b) ──────────────────
echo "T5: float_reopen.sh — phase 1 is non-blocking, schedules run-shell -b"
clear_log
bash "$SCRIPTS/float_reopen.sh"
tmux kill-session -t "$TEST_SESSION" 2>/dev/null  # prevent disruptive popup from phase 2
assert_log "phase1 logged"   "\[reopen/p1\] session=$TEST_SESSION"
echo ""

# ── T6: float_reopen.sh --open (phase 2) ─────────────────────────────────────
echo "T6: float_reopen.sh --open — phase 2 reaches open_popup"
clear_log
tmux new-session -d -s "$TEST_SESSION"
timeout 3 bash "$SCRIPTS/float_reopen.sh" --open 2>/dev/null
sleep 0.2
assert_log "phase2 logged"         "\[reopen/p2\] pane=$CURRENT_PANE"
assert_log "popup opened via p2"   "\[popup\] position=center"
echo ""

# ── Cleanup ──────────────────────────────────────────────────────────────────
tmux kill-session -t "$TEST_SESSION" 2>/dev/null
tmux setenv -gu FLOATX_DEBUG        2>/dev/null
tmux setenv -gu FLOATX_SESSION      2>/dev/null
tmux setenv -gu FLOATX_PANE         2>/dev/null
tmux setenv -gu FLOATX_POSITION     2>/dev/null
tmux setenv -gu FLOATX_LAUNCH_1_CMD 2>/dev/null

echo "─────────────────────────────────────────"
echo "Results: $PASS passed, $FAIL failed"
echo "Log: $LOG_FILE"
[ "$FAIL" -eq 0 ]
