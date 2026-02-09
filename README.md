# zac (zsh-appearance-control)

<p align="center">
  <img src="logo/logo-zsh-appearance-control.png" alt="zsh-appearance-control logo" width="250" />
</p>

`zsh-appearance-control` makes switching between light and dark terminal themes feel smooth, and helps keep your shells and tools in sync with your OS appearance.

It gives you two things:

1) a shared, always-updated “dark or light?” flag (tmux option or cache file)
2) a safe way to nudge running shells to resync when that flag changes

If you use tmux, it integrates especially smoothly: tmux can hold the shared flag as `@dark_appearance`, so every pane sees the same truth. If you do not use tmux, the plugin uses a small cache file instead.

This README also includes minimal, working examples of what that enables:

- tmux theme switching — see [tmux](#tmux-theme-switching-with-dark_appearance)
- Neovim auto theme switching (by watching the appearance file) — see [Neovim](#neovim-switch-running-instances-on-change)
- Emacs auto theme switching (by watching the appearance file) — see [Emacs](#emacs-auto-switch-catppuccin-flavour)

It’s designed to be calm and predictable:

- it does not constantly poll your system
- it does not run heavy commands every time your prompt is drawn
- it updates when something tells it “the appearance changed”

## Is this plugin for you?

This plugin is for people who like their terminal to feel coherent.

If you switch your system between light and dark mode, you probably want more than just the terminal window to change: you want tmux to pick a matching theme, you want your prompt to adjust, and you may want tools like fzf to use different colors.

The hard part is that your shell doesn’t automatically hear about OS appearance changes.
So most setups end up either polling (slow and annoying) or having a handful of custom scripts that don’t quite agree.

`zsh-appearance-control` gives you a clean place to store “dark or light?” and a simple way to react when it changes.
You can wire it to your terminal’s appearance hooks (for example WezTerm), or you can change appearance manually with `zac`.

## How it works (in plain words)

Your terminal (or a tiny helper you run) notices when the system appearance changes.
It then nudges your shells.

Inside each shell, the plugin keeps a small cached value (`0` or `1`) and runs your callback (optional) so you can adjust your shell environment.

There are two “places” the plugin can read from:

- If you are inside tmux, tmux option `@dark_appearance` is the source of truth.
- If you are not inside tmux, a small cache file is used (in your user cache directory).

## Install

However you install it, set any `ZAC_*` environment variables *before* the plugin is loaded (usually in your `.zshrc`, above the plugin line).

### Oh My Zsh

Clone this repo into your Oh My Zsh custom plugins directory:

```zsh
git clone https://github.com/alberti42/zsh-appearance-control.git \
  "$ZSH_CUSTOM/plugins/zsh-appearance-control"
```

Then add it to your plugins list in `.zshrc`:

```zsh
plugins=(... zsh-appearance-control)
```

### DIY (no plugin manager)

Clone the repo anywhere you like, then source the entry file from `.zshrc`:

```zsh
source "/path/to/zsh-appearance-control/zsh-appearance-control.plugin.zsh"
```

After installing, restart your terminal (or start a new shell).

## Everyday use

Most people don’t interact with the plugin directly. You either:

- let your terminal handle appearance changes (recommended), or
- manually switch with `zac`.

### The `zac` command

The plugin provides a `zac` command:

- `zac status` prints `1` for dark and `0` for light. If the value is unknown, it still prints `0` and exits with a non-zero status.
- `zac sync` refreshes the cached value from the current source of truth.
- `zac dark`, `zac light`, `zac toggle` ask your OS to switch appearance, and then update the current shell immediately.

On macOS, switching is done via the system appearance setting.
On Linux, GNOME is supported via the GNOME setting.

### If you want your shell to react

You can provide a callback function name via an environment variable.
When the cached value changes, the plugin will call your function with one argument:

- `1` for dark
- `0` for light

Example idea: export a few variables your theme reads. Here is a minimal example that tweaks fzf colors depending on appearance:

```zsh
my_zac_callback() {
  local is_dark=$1

  if (( is_dark )); then
    export FZF_DEFAULT_OPTS='--color=bg+:#1f2430,fg:#c8d3f5,hl:#82aaff'
  else
    export FZF_DEFAULT_OPTS='--color=bg+:#f2f2f2,fg:#2d2a2e,hl:#005f87'
  fi
}

# Export this variable before loading zsh-appearance-control
export ZAC_CALLBACK_FNC=my_zac_callback
```

## Connecting it to your terminal (the “watcher”)

The plugin does not try to guess when your system appearance changes.
Instead, you (or your terminal) call a tiny helper script when the appearance changes.

This repo ships a standalone dispatcher:

- `bin/appearance-dispatch tmux <on|off|1|0|true|false>`
- `bin/appearance-dispatch cache <on|off|1|0|true|false>`

Which one should you use?

- Use `tmux` when you live inside tmux and want tmux to be the source of truth.
- Use `cache` when you are not in tmux (or you want a simple file-based source of truth).

The dispatcher is careful about signaling: in `cache` mode it only signals shell processes that have opted in (shells that loaded this plugin), so it avoids accidentally sending signals to unrelated shells.

<details>
<summary><strong>TL;DR: cache updates (in-place vs atomic)</strong></summary>

In `cache` mode the appearance file is updated “in place” by default. In plain words: we overwrite the contents of the same file, so it stays the same file on disk. This keeps file watchers simple.

If you set `ZAC_CACHE_ATOMIC=1`, updates become “atomic”: the dispatcher writes a temporary file and then swaps it into place. This is more crash-proof, but given the tiny size of the `0/1` flag a read/write race is extremely unlikely (dark mode changes and your TUI reads the flag in that split-second). Choose atomic mode if you want peace of mind that shell scripts always read a valid value.

There is a tradeoff: because atomic mode replaces the file each time (the inode changes), tools that watch files (like editor configs) must watch the directory rather than the file itself.

</details>

## Debugging

If you want to see what the plugin is doing, you can turn on debug logging:

```zsh
export ZAC_DEBUG=1
```

Then, in one terminal:

```zsh
zac debug console
```

This shows a live log stream while you trigger appearance changes.

## Optional extra: ssh-tmux

If enabled (default), this plugin also provides `ssh-tmux`.

It works like `ssh` (same arguments), but it automatically attaches to a remote tmux session and makes sure the session has `@dark_appearance` set.

You can disable it by setting:

```zsh
export ZAC_ENABLE_SSH_TMUX=0
```

You can customize the remote tmux session name (default: `main`):

```zsh
export ZAC_SSH_TMUX_SESSION=main
```

## Configuration

Configuration is done with environment variables (set them before the plugin is loaded):

- `ZAC_CALLBACK_FNC` name of a function to call when appearance changes
- `ZAC_CACHE_DIR` where to store the non-tmux cache file and pid registry
- `ZAC_LINUX_DESKTOP` set to `gnome` to force GNOME support, or `none` to disable it
- `ZAC_DEBUG` set to `1` to enable debug logging
- `ZAC_ENABLE_SSH_TMUX` set to `0` to disable the `ssh-tmux` extra

## A note on watchers

Different terminals and desktops offer different ways to react to appearance changes.
WezTerm is a great option because it can run a command when the appearance changes.

If your terminal does not offer hooks, you can still use this plugin:

- switch manually with `zac dark/light/toggle`, or
- write a small watcher script/service that calls `bin/appearance-dispatch` when your system appearance changes.

### Example: WezTerm appearance hook

WezTerm can run a command when the system appearance changes. Here is a sketch you can adapt:

```lua
local wezterm = require 'wezterm'

local home = os.getenv('HOME')
local zac_dispatcher = home .. '/path/to/zsh-appearance-control/bin/appearance-dispatch'

local function scheme_for_appearance(appearance)
  local is_dark = appearance:find('Dark') ~= nil
  local dark = is_dark and '1' or '0'

  -- Choose where to dispatch:
  -- - "tmux"  keeps tmux @dark_appearance updated
  -- - "cache" updates a small cache file for non-tmux shells
  wezterm.run_child_process({ zac_dispatcher, 'tmux', dark })
  wezterm.run_child_process({ zac_dispatcher, 'cache', dark })

  return is_dark and 'My Dark Scheme' or 'My Light Scheme'
end

wezterm.on('window-config-reloaded', function(window, pane)
  local overrides = window:get_config_overrides() or {}
  overrides.color_scheme = scheme_for_appearance(window:get_appearance())
  window:set_config_overrides(overrides)
end)
```

If you already know you only use tmux (or only use non-tmux shells), you can remove the dispatch you do not need.

## tmux: theme switching with @dark_appearance

tmux is a great place to keep a single “appearance flag” that all panes can share.

When your OS switches between light and dark mode, a watcher (for example WezTerm) can update tmux option `@dark_appearance`.
From there, your tmux theme can instantly switch palettes, and every shell inside tmux can sync its own environment on the next prompt.

The key idea is simple:

- keep a boolean option in tmux: `@dark_appearance` (`1` for dark, `0` for light)
- define your theme colors in terms of that flag

Here is a tiny sketch:

```tmux
# ~/.tmux.conf
source-file "$HOME/.config/tmux/catppuccin.conf"
```

```tmux
# ~/.config/tmux/catppuccin.conf
set-option -g @dark_appearance 0
```

This repo includes a complete example you can copy and adapt:

- `examples/tmux/catppuccin.conf`

## Neovim: switch running instances on change

If you want Neovim to react to the same appearance changes as your shells, a great approach is to watch a file and react when it changes.

Henrik Sommerfeld has a nice write-up of that file-watching technique for Neovim:

- https://www.henriksommerfeld.se/neovim-automatic-light-dark-mode-switcher/

`zsh-appearance-control` helps by providing a shared, simple “dark or light?” flag that other tools can consume.
Instead of inventing your own `~/.theme` convention, you can reuse the plugin’s cache file:

- `ZAC_CACHE_DIR/appearance` (default: `~/.cache/zac/appearance`)

That file contains a single character:

- `1` for dark
- `0` for light

Your watcher updates it by calling `bin/appearance-dispatch cache ...`, and then your shells (and Neovim) can react.

Here is a minimal sketch (inspired by the same mechanics Henrik describes) that watches the file and switches Neovim’s background:

This uses Neovim’s built-in file watching (libuv via `vim.uv`), so you do not need to install any extra Neovim plugin.
If you are on an older Neovim version that does not have `vim.uv`, try replacing it with `vim.loop`.

### Where do I put this?

If you are new to Neovim config, a simple way to try this is:

1) Create a file named `auto-color-scheme.lua` in your Neovim config directory.

On most systems, that directory is:

- `~/.config/nvim/`

So the full path would be:

- `~/.config/nvim/auto-color-scheme.lua`

2) Paste the Lua code below into that file.

3) In your `init.lua`, load it with:

```lua
-- Load auto-color-scheme:
-- watches ZAC_CACHE_DIR/appearance (0/1) and switches colorscheme live.
dofile(vim.fn.stdpath("config") .. "/auto-color-scheme.lua")
```

```lua
local uv = vim.uv

local function zac_appearance_file()
  local cache = os.getenv("ZAC_CACHE_DIR")
  if not cache or cache == "" then
    cache = (os.getenv("XDG_CACHE_HOME") or (os.getenv("HOME") .. "/.cache")) .. "/zac"
  end
  return cache .. "/appearance"
end

local function read_mode(path)
  local f = io.open(path, "r")
  if not f then
    return "0"
  end
  local line = f:read("*line") or "0"
  f:close()
  return line
end

local function apply_mode(mode)
  if mode == '1' then
    vim.o.background = 'dark'
    pcall(vim.cmd.colorscheme, 'catppuccin-macchiato')
    -- vim.notify("Switching to dark mode 🌘")
  else
    vim.o.background = 'light'
    pcall(vim.cmd.colorscheme, 'catppuccin-frappe')
    -- vim.notify("Switching to light mode 🌖")
  end
end

local path = zac_appearance_file()

-- Apply once on startup.
vim.schedule(function()
  apply_mode(read_mode(path))
end)

-- Watch for changes.
local handle = uv.new_fs_event()
if handle then
  uv.fs_event_start(handle, path, {}, function(err)
    if err then
      return
    end
    vim.schedule(function()
      apply_mode(read_mode(path))
    end)
  end)
end
```

## Emacs: auto switch Catppuccin flavour

Emacs also has built-in file watching, so you can use the same idea: watch the appearance file and switch theme when it changes.

If you use the Catppuccin theme for Emacs, this minimal setup switches between `macchiato` (dark) and `frappe` (light) based on `ZAC_CACHE_DIR/appearance`:

```elisp
;; Catppuccin for Emacs https://github.com/catppuccin/emacs
(use-package catppuccin-theme)

(require 'subr-x)

(defvar zac--watch nil)
(defvar zac--last-catppuccin-flavor nil)

(defun zac--appearance-file ()
  (expand-file-name
   "appearance"
   (or (getenv "ZAC_CACHE_DIR")
       (expand-file-name "zac" (or (getenv "XDG_CACHE_HOME")
                                   (expand-file-name "~/.cache"))))))

(defun zac--read-appearance ()
  (when (file-readable-p (zac--appearance-file))
    (string-trim
     (with-temp-buffer
       (insert-file-contents (zac--appearance-file))
       (buffer-string)))))

(defun zac--apply-appearance ()
  (let* ((v (zac--read-appearance))
         (flavor (if (string= v "1") 'macchiato 'frappe)))
    (unless (eq zac--last-catppuccin-flavor flavor)
      (setq zac--last-catppuccin-flavor flavor)
      (setq catppuccin-flavor flavor)
      (mapc #'disable-theme custom-enabled-themes)
      (load-theme 'catppuccin t)
      ;; Optional: keep terminal Emacs backgrounds transparent
      (set-face-attribute 'default nil :background "unspecified-bg")
      (set-face-attribute 'mode-line nil :background "unspecified-bg")
      (set-face-attribute 'mode-line-inactive nil :background "unspecified-bg"))))

(defun zac-watch-start ()
  (interactive)
  (zac--apply-appearance)
  (when (fboundp 'file-notify-add-watch)
    (unless zac--watch
      (setq zac--watch
            (file-notify-add-watch
             (zac--appearance-file)
             '(change)
             (lambda (_event)
               (zac--apply-appearance)))))))

;; Start watcher automatically.
(zac-watch-start)
```

Now, whenever your watcher updates `ZAC_CACHE_DIR/appearance` (via `bin/appearance-dispatch cache ...`), Emacs can follow along.

## Author
- **Author:** Andrea Alberti
- **GitHub Profile:** [alberti42](https://github.com/alberti42)
- **Donations:** [![Buy Me a Coffee](https://img.shields.io/badge/Donate-Buy%20Me%20a%20Coffee-orange)](https://buymeacoffee.com/alberti)

Feel free to contribute to the development of this plugin or report any issues in the [GitHub repository](https://github.com/alberti42/zsh-appearance-control/issues).

## License

This project is licensed under the MIT License. See the [LICENSE](LICENSE) file for details.
