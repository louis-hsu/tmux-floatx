#!/usr/bin/env bash
# Tests for the floatx dock flow (move float pane into a new window in origin).
# Run: bash tests/test_dock.sh
# Requirements: tmux server running (any session). Uses throwaway sessions only.

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

assert_eq() {
    local desc="$1" expected="$2" actual="$3"
    if [ "$expected" = "$actual" ]; then
        pass "$desc"
    else
        fail "$desc  [expected: $expected, got: $actual]"
    fi
}

clear_log() { : > "$LOG_FILE"; }

# Run dock.sh as if the key fired inside the float with active pane $1.
# display-message -p and detach-client are mocked (no real client involved);
# everything else goes to real tmux. $2 overrides the reported session name.
run_dock() {
    (
        export MOCK_FP="$1" MOCK_SESSION="${2:-$FLOAT_SESSION}"
        tmux() {
            case "$*" in
                "display-message -p #{session_name}") echo "$MOCK_SESSION" ;;
                "display-message -p #{pane_id}")      echo "$MOCK_FP" ;;
                detach-client)  floatx_log "[test] mock: detach-client called" ;;
                display-message*) floatx_log "[test] mock: display-message $*" ;;
                *)              command tmux "$@" ;;
            esac
        }
        export -f tmux
        bash "$SCRIPTS/dock.sh"
    )
}

# ── prerequisite ─────────────────────────────────────────────────────────────

if ! tmux info &>/dev/null; then
    echo "ERROR: no tmux server running. Start a tmux session first."
    exit 1
fi

# Snapshot live FLOATX_* env and float root bindings — tests overwrite them,
# and the user's real float config must survive the run.
ENV_SNAPSHOT="$(mktemp)"; KEYS_SNAPSHOT="$(mktemp)"
tmux showenv -g | grep '^FLOATX_' > "$ENV_SNAPSHOT"
tmux list-keys -T root | grep -E ' C-(Right|Left|Up|Down) ' > "$KEYS_SNAPSHOT"

export FLOAT_SESSION="floatx_dtest_float_$$"
ORIGIN_SESSION="floatx_dtest_origin_$$"

echo "=== tmux-floatx dock tests ==="
echo ""

setup() {
    tmux kill-session -t "$FLOAT_SESSION"  2>/dev/null
    tmux kill-session -t "$ORIGIN_SESSION" 2>/dev/null
    tmux new-session -d -s "$ORIGIN_SESSION"
    tmux new-session -d -s "$FLOAT_SESSION"
    tmux setenv -g FLOATX_DEBUG     "on"
    tmux setenv -g FLOATX_SESSION   "$FLOAT_SESSION"
    tmux setenv -g FLOATX_ORIGIN    "$ORIGIN_SESSION"
    tmux setenv -g FLOATX_ORIGIN_ID "$(tmux display-message -p -t "$ORIGIN_SESSION" '#{session_id}')"
    tmux setenv -g FLOATX_BIND_DOCK "C-Down"
}

# ── T1: dock moves active pane out of a multi-pane float ─────────────────────
echo "T1: dock.sh — moves float pane into new window in origin"
setup; clear_log
tmux split-window -d -t "$FLOAT_SESSION"
fp="$(tmux display-message -p -t "$FLOAT_SESSION" '#{pane_id}')"
before="$(tmux list-windows -t "$ORIGIN_SESSION" | wc -l | tr -d ' ')"
run_dock "$fp"
after="$(tmux list-windows -t "$ORIGIN_SESSION" | wc -l | tr -d ' ')"
assert_eq  "origin gained a window"     "$((before+1))" "$after"
assert_eq  "pane now lives in origin"   "$ORIGIN_SESSION" "$(tmux display-message -p -t "$fp" '#{session_name}')"
assert_eq  "new window is current"      "$fp" "$(tmux display-message -p -t "$ORIGIN_SESSION" '#{pane_id}')"
assert_eq  "float keeps other pane"     "1" "$(tmux list-panes -t "$FLOAT_SESSION" | wc -l | tr -d ' ')"
assert_log "dock logged"                "\[dock\] fp=$fp origin="
assert_log "popup detached"             "\[test\] mock: detach-client called"
echo ""

# ── T2: docking the last pane removes the float session ──────────────────────
echo "T2: dock.sh — last pane in float → float session destroyed"
setup; clear_log
fp="$(tmux display-message -p -t "$FLOAT_SESSION" '#{pane_id}')"
run_dock "$fp"
assert_eq  "pane now lives in origin"   "$ORIGIN_SESSION" "$(tmux display-message -p -t "$fp" '#{session_name}')"
if tmux has-session -t "$FLOAT_SESSION" 2>/dev/null; then
    fail "float session destroyed"
else
    pass "float session destroyed"
fi
echo ""

# ── T3: origin by ID survives rename ─────────────────────────────────────────
echo "T3: dock.sh — origin renamed after toggle still resolves via ID"
setup; clear_log
tmux split-window -d -t "$FLOAT_SESSION"
renamed="${ORIGIN_SESSION}_renamed"
tmux rename-session -t "$ORIGIN_SESSION" "$renamed"
fp="$(tmux display-message -p -t "$FLOAT_SESSION" '#{pane_id}')"
run_dock "$fp"
assert_eq  "pane lives in renamed origin" "$renamed" "$(tmux display-message -p -t "$fp" '#{session_name}')"
tmux kill-session -t "$renamed" 2>/dev/null
echo ""

# ── T4: missing origin aborts ────────────────────────────────────────────────
echo "T4: dock.sh — origin session gone → no move"
setup; clear_log
fp="$(tmux display-message -p -t "$FLOAT_SESSION" '#{pane_id}')"
tmux kill-session -t "$ORIGIN_SESSION"
run_dock "$fp"
assert_log     "origin missing logged"  "\[dock\] origin missing"
assert_not_log "no detach"              "\[test\] mock: detach-client called"
assert_eq      "pane still in float"    "$FLOAT_SESSION" "$(tmux display-message -p -t "$fp" '#{session_name}')"
echo ""

# ── T5: guard outside float ──────────────────────────────────────────────────
echo "T5: dock.sh — fired outside float session → no-op"
setup; clear_log
fp="$(tmux display-message -p -t "$FLOAT_SESSION" '#{pane_id}')"
run_dock "$fp" "some_other_session"
assert_not_log "no dock"                "\[dock\]"
assert_eq      "pane still in float"    "$FLOAT_SESSION" "$(tmux display-message -p -t "$fp" '#{session_name}')"
echo ""

# ── T6: bindings pass key through outside float ──────────────────────────────
echo "T6: set_move_bindings — keys use session filter with send-keys passthrough"
setup
tmux setenv -g FLOATX_BIND_RIGHT  "C-Right"
tmux setenv -g FLOATX_BIND_LEFT   "C-Left"
tmux setenv -g FLOATX_BIND_RESUME "C-Up"
(
    source "$SCRIPTS/utils.sh"
    set_move_bindings
)
for key in C-Right C-Left C-Up C-Down; do
    line="$(tmux list-keys -T root | grep -E " $key +")"
    if echo "$line" | grep -q "session_name},$FLOAT_SESSION" && echo "$line" | grep -q "send-keys $key"; then
        pass "$key bound with passthrough"
    else
        fail "$key bound with passthrough  [got: $line]"
    fi
done
(
    source "$SCRIPTS/utils.sh"
    unset_move_bindings
)
if tmux list-keys -T root | grep -q dock.sh; then
    fail "dock key unbound"
else
    pass "dock key unbound"
fi
echo ""

# ── Cleanup ──────────────────────────────────────────────────────────────────
tmux kill-session -t "$FLOAT_SESSION"  2>/dev/null
tmux kill-session -t "$ORIGIN_SESSION" 2>/dev/null
tmux showenv -g | grep '^FLOATX_' | cut -d= -f1 | while read -r v; do
    tmux setenv -gu "$v"
done
while IFS='=' read -r k v; do
    tmux setenv -g "$k" "$v"
done < "$ENV_SNAPSHOT"
[ -s "$KEYS_SNAPSHOT" ] && tmux source-file "$KEYS_SNAPSHOT"
rm -f "$ENV_SNAPSHOT" "$KEYS_SNAPSHOT"

echo "─────────────────────────────────────────"
echo "Results: $PASS passed, $FAIL failed"
echo "Log: $LOG_FILE"
[ "$FAIL" -eq 0 ]
