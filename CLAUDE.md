# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A tmux plugin (bash) that creates a floating terminal popup. It manages a dedicated tmux session displayed as an overlay, with support for left/right/center positioning and position memory between toggles.

## No build or test pipeline

There is no build step, test suite, or linter. Manual testing requires a live tmux session. To reload after changes:

```bash
tmux source-file ~/.tmux.conf   # re-applies @floatx-* options
bash /path/to/floatx.tmux       # re-runs the plugin entry point
```

Debug log: `tail -f /tmp/floatx_debug.log`

## Architecture

State lives entirely in tmux global environment variables (`FLOATX_*`), set via `tmux setenv -g`. No files are written except the debug log.

### Entry point: `floatx.tmux`

Runs once at load time. Reads `@floatx-*` options from `tmux.conf` via `tmux_opt_consume` (which also unsets each option after reading, preventing stale values on reload), converts them to `FLOATX_*` env vars, and binds keys.

### `scripts/utils.sh`

Shared library sourced by all scripts. Key functions:
- `tmux_opt` / `tmux_opt_consume` — read tmux options with defaults
- `env_val` — read from tmux global env
- `parse_kv` / `pct_to_abs` — parse `w=80%,h=80%` size strings and convert to absolute pixel counts
- `set_move_bindings` / `unset_move_bindings` — bind/unbind Ctrl+arrow keys in the root key table (no prefix). These are only active while inside the float session.
- `open_popup` — builds and fires the `tmux popup` command for the current `FLOATX_POSITION`

### `scripts/toggle.sh`

Called on `<prefix>+p`. Detects whether the active session is the float session:
- If inside float → `unset_move_bindings` + `detach-client` (hides popup)
- If outside float → captures terminal dimensions + pane/client IDs into `FLOATX_*` env vars, creates the float session if needed, calls `set_move_bindings` + `open_popup`

### `scripts/position.sh`

Called by move key bindings with `left`, `right`, or `center` as argument. Pressing the same direction twice toggles back to center. Re-reads terminal dimensions via `stty size` on the stored TTY path (bypasses tmux to get true OS-level dimensions), updates `FLOATX_POSITION`, detaches, then calls `open_popup`.

### Size geometry

- **Center:** `w%` and `h%` are percentages of the full terminal; tmux handles centering via `-x C -y C`.
- **Left/Right:** `w%` is relative to *half* the terminal width. Absolute pixel position is computed manually to center the popup within that half.
