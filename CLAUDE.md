# CLAUDE.md

tmux plugin (pure bash, no build): floating popup pane with center/left/right docking, plus `@floatx-launch-N` launcher popups. User docs in `README.md`.

## Layout

- `floatx.tmux` — entry point (TPM / `run-shell`). Reads `@floatx-*` options, stores them in tmux global env as `FLOATX_*`, binds prefix keys.
- `scripts/utils.sh` — shared helpers, sourced by every script: `env_val`, `tmux_opt_consume`, `parse_kv`, `set/unset_move_bindings`, `open_popup`, `open_launcher_popup`, `floatx_log`.
- `scripts/toggle.sh` — prefix+toggle key. Inside float session → detach; outside → capture origin pane/client/size, create session if missing, open popup.
- `scripts/position.sh <left|right|center>` — Ctrl+arrow handler; same direction twice → center. Re-reads terminal size via `stty size < $FLOATX_CLIENT_TTY`, detaches, reopens.
- `scripts/dock.sh` — dock key handler. `break-pane` moves float's active pane into new window of origin session (`FLOATX_ORIGIN_ID`), detaches popup, selects new window. Last float pane → float session dies (toggle recreates).
- `scripts/launch.sh <N>` — launcher key handler. From inside float: detach, run cmd, then chain `float_reopen.sh` to restore float.
- `scripts/float_reopen.sh` — two-phase reopen: phase 1 runs inside launcher popup and schedules phase 2 (`--open`) via `run-shell -b` (avoids nested-popup restriction).
- `tests/test_launcher_reopen.sh` — log-based tests for launcher/reopen flow.
- `tests/test_dock.sh` — dock tests against real throwaway sessions.
- `tests/helpers.sh` — `snapshot_floatx_state` / `register_test_session`; EXIT trap restores live `FLOATX_*` env + floatx root bindings and kills test sessions.

## State model

All runtime state lives in **tmux global environment** (`tmux setenv -g FLOATX_*`), not files or shell vars — each keypress is a fresh `run-shell` process. Key vars: `FLOATX_POSITION`, `FLOATX_PANE`, `FLOATX_ORIGIN_ID` (session id, rename-safe), `FLOATX_CLIENT_TTY`, `FLOATX_WIN_W/H`, `FLOATX_BIND_*`, `FLOATX_LAUNCH_<N>_KEY/CMD`, `FLOATX_LAUNCH_COUNT`.

Read with `env_val`, never parse `showenv` directly.

## Invariants / gotchas

- Options read via `tmux_opt_consume` (read then **unset**) so options removed from tmux.conf don't survive reload. Plugin must re-run after each `source-file`.
- On reload, previous bindings (toggle, move keys, launcher keys) are unbound using stored `FLOATX_BIND_*` / `FLOATX_LAUNCH_*` before rebinding. Keep this when adding new keys.
- Move/dock keys are root-table (`bind -n`) and only bound while float open. Every path that leaves the float must call `unset_move_bindings` before `detach-client`.
- Root bindings are server-wide: bind via `bind_float_key` (`if-shell -F` on session name, else `send-keys` passthrough) so keys aren't swallowed in other panes/clients or after the float exits via `exit` (stale bindings). Script guards must not call `unset_move_bindings` — another client may still have float open.
- Capture client dims/pane **before** `detach-client`; after detach, `display-message` resolves the wrong client. Popups target `-t "$FLOATX_PANE"` for the same reason.
- Left/right width % is relative to **half** terminal width; computed to absolute cols in `open_popup`. Center uses tmux `-x C -y C` with % directly.
- Launcher cmd runs via `$SHELL -ic` so user aliases/functions resolve.
- Arrow key names must be capitalized for tmux (`C-Right`); `make_ctrl_key` in `floatx.tmux` handles it.

## Debugging

`set -g @floatx-debug on` → logs to `/tmp/floatx_debug.log` via `floatx_log` (tags like `[popup]`, `[launch]`, `[reopen/p1]`). Add `floatx_log` calls for new flows; tests assert on these log lines.

Debug mode also changes launcher behavior: `launch.sh` logs a `[snapshot]`, `open_launcher_popup` logs popup rc/stderr, and `launcher_full_cmd` appends stderr/rc capture (`[launcher/exit]`) to the popup cmd. Runtime toggle without reload: `tmux setenv -g FLOATX_DEBUG on`.

## Testing

```bash
bash tests/test_launcher_reopen.sh   # needs running tmux server; T6 opens a real popup briefly
bash tests/test_dock.sh              # needs running tmux server; no popup
shellcheck floatx.tmux scripts/*.sh
```

Tests run on the user's live tmux server: every test file must `source tests/helpers.sh` and call `snapshot_floatx_state` before touching `FLOATX_*` env or bindings, and `register_test_session` for any session it creates. Never `setenv -gu` live vars in cleanup.

Tests mock `tmux` with an exported bash function, passing `showenv` through to real tmux. Log-pattern assertions must track `launcher_full_cmd`'s format (debug variant, since tests run with debug on); T1/T2 pin `SHELL=/bin/bash` and use `assert_log_fixed` (grep -F) since `printf %q` adds backslashes.

Manual check: `tmux source-file ~/.config/tmux/tmux.conf`, then exercise prefix+p, Ctrl+arrows, launcher keys.

## Conventions

- Bash, 4-space indent, `local` vars in functions, `_`-prefixed globals in `floatx.tmux`.
- Each script starts with `CURRENT_DIR=...; source "$CURRENT_DIR/utils.sh"`.
- Session name fallback: `[ -z "$session" ] && session="$DEFAULT_SESSION"`.
- New user option → add default in `floatx.tmux`, row in README config table.
- Conventional-commit style messages (`feat:`, `fix:`).
