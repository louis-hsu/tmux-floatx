# CLAUDE.md

tmux plugin (pure bash, no build): floating popup pane with center/left/right docking, plus `@floatx-launch-N` launcher popups. User docs in `README.md`.

## Layout

- `floatx.tmux` — entry point (TPM / `run-shell`). Reads `@floatx-*` options, stores them in tmux global env as `FLOATX_*`, binds prefix keys.
- `scripts/utils.sh` — shared helpers, sourced by every script: `env_val`, `tmux_opt_consume`, `parse_kv`, `set/unset_move_bindings`, `open_popup`, `open_launcher_popup`, `floatx_log`.
- `scripts/toggle.sh` — prefix+toggle key. Inside float session → detach; outside → capture origin pane/client/size, create session if missing, open popup.
- `scripts/position.sh <left|right|center>` — Ctrl+arrow handler; same direction twice → center. Re-reads terminal size via `stty size < $FLOATX_CLIENT_TTY`, detaches, reopens.
- `scripts/launch.sh <N>` — launcher key handler. From inside float: detach, run cmd, then chain `float_reopen.sh` to restore float.
- `scripts/float_reopen.sh` — two-phase reopen: phase 1 runs inside launcher popup and schedules phase 2 (`--open`) via `run-shell -b` (avoids nested-popup restriction).
- `tests/test_launcher_reopen.sh` — log-based tests for launcher/reopen flow.

## State model

All runtime state lives in **tmux global environment** (`tmux setenv -g FLOATX_*`), not files or shell vars — each keypress is a fresh `run-shell` process. Key vars: `FLOATX_POSITION`, `FLOATX_PANE`, `FLOATX_CLIENT_TTY`, `FLOATX_WIN_W/H`, `FLOATX_BIND_*`, `FLOATX_LAUNCH_<N>_KEY/CMD`, `FLOATX_LAUNCH_COUNT`.

Read with `env_val`, never parse `showenv` directly.

## Invariants / gotchas

- Options read via `tmux_opt_consume` (read then **unset**) so options removed from tmux.conf don't survive reload. Plugin must re-run after each `source-file`.
- On reload, previous bindings (toggle, move keys, launcher keys) are unbound using stored `FLOATX_BIND_*` / `FLOATX_LAUNCH_*` before rebinding. Keep this when adding new keys.
- Move keys are root-table (`bind -n`) and only bound while float open. Every path that leaves the float must call `unset_move_bindings` before `detach-client`.
- Capture client dims/pane **before** `detach-client`; after detach, `display-message` resolves the wrong client. Popups target `-t "$FLOATX_PANE"` for the same reason.
- Left/right width % is relative to **half** terminal width; computed to absolute cols in `open_popup`. Center uses tmux `-x C -y C` with % directly.
- Launcher cmd runs via `$SHELL -ic` so user aliases/functions resolve.
- Arrow key names must be capitalized for tmux (`C-Right`); `make_ctrl_key` in `floatx.tmux` handles it.

## Debugging

`set -g @floatx-debug on` → logs to `/tmp/floatx_debug.log` via `floatx_log` (tags like `[popup]`, `[launch]`, `[reopen/p1]`). Add `floatx_log` calls for new flows; tests assert on these log lines.

## Testing

```bash
bash tests/test_launcher_reopen.sh   # needs running tmux server; T6 opens a real popup briefly
shellcheck floatx.tmux scripts/*.sh
```

Tests mock `tmux` with an exported bash function, passing `showenv` through to real tmux. Log-pattern assertions must track `open_launcher_popup`'s `full_cmd` format; T1/T2 pin `SHELL=/bin/bash` and use `assert_log_fixed` (grep -F) since `printf %q` adds backslashes.

Manual check: `tmux source-file ~/.config/tmux/tmux.conf`, then exercise prefix+p, Ctrl+arrows, launcher keys.

## Conventions

- Bash, 4-space indent, `local` vars in functions, `_`-prefixed globals in `floatx.tmux`.
- Each script starts with `CURRENT_DIR=...; source "$CURRENT_DIR/utils.sh"`.
- Session name fallback: `[ -z "$session" ] && session="$DEFAULT_SESSION"`.
- New user option → add default in `floatx.tmux`, row in README config table.
- Conventional-commit style messages (`feat:`, `fix:`).
