# tmux-floatx

A tmux plugin that provides a floating terminal window with support for left, right, and center positioning — all without leaving the keyboard.

## Features

- Toggle a floating terminal with a single prefix key
- Move the float to the left or right half of the terminal
- Resume to center at any time
- Position memory: the float stays where you left it between toggles
- Fully customizable size, session name, title, and border color
- Move keys are only active while the float window is open (no accidental session detach)

## Requirements

- tmux 3.3+

## Installation

### Via TPM

Add to `~/.tmux.conf`:

```tmux
set -g @plugin 'louis-hsu/tmux-floatx'
run '~/.tmux/plugins/tpm/tpm'
```

### Manual

Add at the **end** of `~/.tmux.conf` (after all `@floatx-*` options):

```tmux
run-shell "/path/to/tmux-floatx/floatx.tmux"
```

## Keybindings

| Key | Action |
|---|---|
| `prefix` + `p` | Toggle float window show/hide |
| `Ctrl` + `Right` | Move float to right half |
| `Ctrl` + `Left` | Move float to left half |
| `Ctrl` + `Up` | Resume float to center |

Move keys (`Ctrl+*`) are only active while the float window is open.

## Configuration

All options are set in `~/.tmux.conf` before the plugin is loaded.

| Option | Default | Description |
|---|---|---|
| `@floatx-size` | `w=80%,h=80%` | Center popup size |
| `@floatx-right-size` | `w=85%,h=90%` | Size when docked right |
| `@floatx-left-size` | `w=85%,h=90%` | Size when docked left |
| `@floatx-session-name` | `floatx` | tmux session name for the float window |
| `@floatx-title` | `MyFloatx` | Title shown in the top border |
| `@floatx-border-color` | `colour214` | Border color |
| `@floatx-bind-toggle` | `p` | Toggle key (used with prefix) |
| `@floatx-bind-right` | `right` | Move-right key (becomes `Ctrl+key`) |
| `@floatx-bind-left` | `left` | Move-left key (becomes `Ctrl+key`) |
| `@floatx-bind-resume` | `up` | Resume-center key (becomes `Ctrl+key`) |

### Size format

`w=80%,h=80%` — width and height as percentages.

- **Center:** both `w%` and `h%` are relative to the full terminal dimensions.
- **Left/Right:** `w%` is relative to **half** the terminal width; `h%` is relative to the full height. The popup is centered within its half.

### Border color format

Accepts any tmux style color:

- Named colors: `red`, `magenta`, `cyan`, `blue`, …
- 256-color: `colour0` – `colour255`
- Hex RGB: `#FF8800` (requires tmux 3.2+)

### Example configuration

```tmux
set -g @floatx-size           "w=75%,h=75%"
set -g @floatx-right-size     "w=90%,h=90%"
set -g @floatx-left-size      "w=90%,h=90%"
set -g @floatx-session-name   "scratch"
set -g @floatx-title          "Terminal"
set -g @floatx-border-color   "#FF8800"
set -g @floatx-bind-toggle    "f"
set -g @floatx-bind-right     "right"
set -g @floatx-bind-left      "left"
set -g @floatx-bind-resume    "up"

run-shell "/path/to/tmux-floatx/floatx.tmux"
```

## Debug log

All popup events are logged to `/tmp/floatx_debug.log`. Monitor in real time:

```bash
tail -f /tmp/floatx_debug.log
```
