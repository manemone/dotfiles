# tmux

Cross-platform tmux configuration with Vim-style keybindings.

## Requirements

- **tmux 3.3+** — older versions may not support the modern mouse and copy-mode syntax.

## Installation

### macOS

```bash
brew install tmux
```

### Linux (Debian/Ubuntu)

```bash
sudo apt update && sudo apt install -y tmux xclip
```

> `xclip` provides system clipboard integration. On Wayland, install `wl-copy` instead.

### WSL (Windows Subsystem for Linux)

Same as Linux above. For clipboard passthrough to Windows, install `xclip` and ensure an X server is running, or use Windows Terminal / WSLg which handle clipboard automatically.

### Deploy

```bash
cd tmux
./deploy.sh
```

The script symlinks `tmux.conf` to `~/.tmux.conf` and installs tmux if needed.

## Keybindings

Prefix: `C-q` (Ctrl+q)

### Panes

| Key | Action |
|-----|--------|
| `Prefix h` | Select pane left |
| `Prefix j` | Select pane down |
| `Prefix k` | Select pane up |
| `Prefix l` | Select pane right |
| `Prefix \|` | Split horizontally |
| `Prefix -` | Split vertically |
| `Prefix H` | Resize pane left (+5) |
| `Prefix J` | Resize pane down (+5) |
| `Prefix K` | Resize pane up (+5) |
| `Prefix L` | Resize pane right (+5) |

### Copy Mode (Vi-style)

| Key | Action |
|-----|--------|
| `v` | Begin selection |
| `V` | Select whole line |
| `Ctrl+v` | Block selection (rectangle) |
| `y` | Copy selection |
| `Y` | Copy whole line |
| `Mouse drag` (in copy mode) | Copy selection to system clipboard (macOS: pbcopy, Linux: xclip/wl-copy) |

### General

| Key | Action |
|-----|--------|
| `Ctrl+p` | Paste buffer |

## Platform-specific behaviour

| Feature | macOS | Linux / WSL |
|---------|-------|-------------|
| Wi-Fi SSID in status bar | ✅ `#(wifi)` | — hidden |
| Battery in status bar | ✅ `#(battery --tmux)` | — hidden |
| Clipboard copy | `pbcopy` (via reattach-to-user-namespace) | `xclip` / `wl-copy` |
