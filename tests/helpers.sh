#!/usr/bin/env bash
# Shared test helpers. Tests run against the user's live tmux server and
# overwrite FLOATX_* global env and float root bindings; snapshot both up front
# and restore on exit so the user's real float config survives the run.
# Usage: source "$REPO/tests/helpers.sh"; snapshot_floatx_state
#        (restore runs automatically via EXIT trap)

_FLOATX_ENV_SNAPSHOT=""
_FLOATX_KEYS_SNAPSHOT=""
_FLOATX_TEST_SESSIONS=()

# Throwaway sessions to kill on exit (covers interrupted runs)
register_test_session() {
    _FLOATX_TEST_SESSIONS+=("$@")
}

# Root-table bindings owned by floatx (move/dock keys)
_floatx_root_keys() {
    tmux list-keys -T root | grep -E 'position\.sh|dock\.sh'
}

snapshot_floatx_state() {
    _FLOATX_ENV_SNAPSHOT="$(mktemp)"
    _FLOATX_KEYS_SNAPSHOT="$(mktemp)"
    tmux showenv -g | grep '^FLOATX_' > "$_FLOATX_ENV_SNAPSHOT"
    _floatx_root_keys > "$_FLOATX_KEYS_SNAPSHOT"
    trap restore_floatx_state EXIT
}

restore_floatx_state() {
    [ -n "$_FLOATX_ENV_SNAPSHOT" ] || return 0
    local k v key s
    for s in "${_FLOATX_TEST_SESSIONS[@]}"; do
        tmux kill-session -t "$s" 2>/dev/null
    done
    tmux showenv -g | grep '^FLOATX_' | cut -d= -f1 | while read -r k; do
        tmux setenv -gu "$k"
    done
    while IFS='=' read -r k v; do
        tmux setenv -g "$k" "$v"
    done < "$_FLOATX_ENV_SNAPSHOT"

    # Drop bindings the tests created, then reinstate the user's originals
    _floatx_root_keys | awk '{for (i=1;i<=NF;i++) if ($i=="root") {print $(i+1); break}}' |
        while read -r key; do tmux unbind -n "$key"; done
    [ -s "$_FLOATX_KEYS_SNAPSHOT" ] && tmux source-file "$_FLOATX_KEYS_SNAPSHOT"

    rm -f "$_FLOATX_ENV_SNAPSHOT" "$_FLOATX_KEYS_SNAPSHOT"
    _FLOATX_ENV_SNAPSHOT=""
}
