# tmux

Cross-platform tmux configuration with Vim-style keybindings and system clipboard integration.

## 1. Requirements

| Tool | Minimum Version | Why |
|---|---|---|
| **tmux** | 3.3+ | Modern mouse and copy-mode syntax (`send -X`), true-color support |

### Install tmux

**macOS (Apple Silicon / Intel)**
```bash
brew install tmux reattach-to-user-namespace
```

`reattach-to-user-namespace` enables system clipboard access from tmux on macOS.

**Linux (Ubuntu/Debian)**
```bash
sudo apt update && sudo apt install tmux xclip
```

`xclip` provides system clipboard integration on X11. On Wayland, use `wl-clipboard`:
```bash
sudo apt install wl-clipboard
```

**WSL2**
```bash
sudo apt update && sudo apt install tmux
```

WSLg / Windows Terminal users get automatic clipboard passthrough to Windows. For older WSL setups, install `xclip` and ensure an X server is running.

## 2. Quick Start

```bash
cd ~/.dotfiles/tmux
./deploy.sh
```

The deploy script:
- Symlinks `tmux.conf` → `~/.tmux.conf`
- Installs tmux if not present:
  - macOS: `brew install tmux reattach-to-user-namespace`
  - Linux: `sudo apt install tmux` (falls back to `brew install tmux` if apt unavailable)
- On WSL, prints clipboard integration notes

Start a new tmux session:
```bash
tmux new-session -s main
# or attach to an existing session:
tmux attach-session -t main
```

## 3. What's Included

### General Settings

| Setting | Value | Notes |
|---|---|---|
| Prefix key | `C-q` | `C-b` is unbound |
| Default shell | User's login shell (`#{SHELL}`) | Works on macOS, Linux, WSL |
| Terminal type | `tmux-256color` | True-color support |
| Base index | 1 | Windows/pane numbers start at 1 |
| Mouse | On | Click to select pane/window, scroll in copy mode |
| Status bar | Top | Left: hostname + pane number; Right: OS info + date/time |

### Status Bar (Platform-Specific)

| Feature | macOS | Linux / WSL |
|---|---|---|
| Wi-Fi SSID | ✅ `#(wifi)` | — hidden |
| Battery | ✅ `#(battery --tmux)` | — hidden |
| Date/Time | ✅ `[%Y-%m-%d(%a) %H:%M]` | ✅ `[%Y-%m-%d(%a) %H:%M]` |

### Keybindings

Prefix: `C-q` (Ctrl+q)

#### Pane Navigation (Vim-style)

| Key | Action |
|---|---|
| `Prefix h` | Select pane left |
| `Prefix j` | Select pane down |
| `Prefix k` | Select pane up |
| `Prefix l` | Select pane right |

#### Pane Splitting

| Key | Action |
|---|---|
| `Prefix \|` | Split horizontally (new pane to the right) |
| `Prefix -` | Split vertically (new pane below) |

#### Pane Resizing

| Key | Action |
|---|---|
| `Prefix H` | Resize left (+5 columns) |
| `Prefix J` | Resize down (+5 rows) |
| `Prefix K` | Resize up (+5 rows) |
| `Prefix L` | Resize right (+5 columns) |

#### Copy Mode (Vi-style)

| Key | Action |
|---|---|
| `v` | Begin selection |
| `V` | Select whole line |
| `Ctrl+v` | Toggle block selection (rectangle) |
| `y` | Copy selection to tmux buffer |
| `Y` | Copy whole line to tmux buffer |
| `Mouse drag` | Copy selection to system clipboard |

#### General

| Key | Action |
|---|---|
| `C-p` | Paste tmux buffer |

### System Clipboard Integration

| Platform | Copy Method |
|---|---|
| macOS | `reattach-to-user-namespace pbcopy` |
| Linux (X11) | `xclip -in -selection clipboard` |
| Linux (Wayland) | `wl-copy` |
| WSL2 (WSLg) | Automatic passthrough to Windows clipboard |

The config uses a fallback chain on Linux: `xclip || wl-copy || true` — it never fails on clipboard operations.

## 4. Customization

### Changing the Prefix Key

Edit `tmux/tmux.conf`:
```
set-option -g prefix C-q    # Change C-q to your preferred key
unbind C-b                  # Change to match the new prefix
```

Then reload: `tmux source-file ~/.tmux.conf`

### Adding Custom Status Bar Info

The status bar is on top with:
- **Left**: `#H:[#P]` — hostname and pane number
- **Right**: OS-dependent (macOS shows Wi-Fi + battery; Linux shows date/time only)

Edit the `status-left` and `status-right` lines in `tmux/tmux.conf` and reload.

### Adding New Keybindings

Edit `tmux/tmux.conf` under the appropriate section. Use:
```
bind <key> <command>
```
For repeatable bindings (resize keys): `bind -r <key> <command>`

Reload with: `tmux source-file ~/.tmux.conf`

### Changing the Status Bar Position

```tmux
# In tmux.conf:
set-option -g status-position bottom   # Move bar to bottom
set-option -g status-position top      # Move bar to top (default)
```

## 5. Troubleshooting

### "tmux 3.3+ required" or copy-mode keys don't work

The config uses `send -X` syntax introduced in tmux 3.3. Check your version:
```bash
tmux -V
```

If older than 3.3:
- **macOS**: `brew upgrade tmux`
- **Linux**: `sudo apt update && sudo apt upgrade tmux` (or install via Homebrew for a newer version)

### Clipboard copy not working (macOS)

Ensure `reattach-to-user-namespace` is installed:
```bash
brew install reattach-to-user-namespace
```

### Clipboard copy not working (Linux)

The config tries `xclip` first, then `wl-copy`. Install whichever matches your display server:
```bash
# X11
sudo apt install xclip

# Wayland
sudo apt install wl-clipboard
```

### Clipboard copy not working (WSL)

WSLg and Windows Terminal handle clipboard automatically. If using an older WSL setup without WSLg:
1. Install an X server on Windows (VcXsrv, X410)
2. Install `xclip`: `sudo apt install xclip`
3. Set `export DISPLAY=:0` in your shell

### Mouse not working

Verify mouse mode is on:
```tmux
# Inside tmux:
tmux show-options -g mouse
# Should show: mouse on
```

If off, add `set-option -g mouse on` to `~/.tmux.conf` and reload.

### True-color / 256-color not displaying correctly

The config sets `default-terminal "tmux-256color"`. Ensure your terminal emulator supports true color:
- **Windows Terminal**: Supported out of the box
- **iTerm2**: Supported out of the box
- **GNOME Terminal**: Supported since 3.36
- **Apple Terminal**: Limited support — consider iTerm2 or Kitty

If colors still look wrong, verify `$TERM` outside tmux:
```bash
echo $TERM
# Should be "xterm-256color" or similar
```
