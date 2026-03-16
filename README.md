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

### zinit

```zsh
zinit lucid wait light-mode for \
    wait'0' \
    atinit"export ZAC_IMMEDIATE_CALLBACK_FNC=my_immediate_callback" \
    atload'zac sync && my_immediate_callback "$REPLY"' \
    path/to/zsh-appearance-control
```

<details>
<summary><strong>A few things worth noting</strong></summary>

- `wait'0'` defers loading until after the first prompt, so the plugin does not slow down shell startup. If your prompt theme needs the appearance applied before the very first draw, load the plugin earlier (remove `wait` entirely or use a lower turbo stage).
- `atinit` sets `ZAC_IMMEDIATE_CALLBACK_FNC` before the plugin is sourced.
- `atload` runs `zac sync` once after the plugin loads to read the current appearance, then calls your immediate callback directly to apply it to the current shell. `zac sync` stores the result in `$REPLY`, so passing it straight to the callback avoids a second query.
- `ZAC_IO_CMD` is read by `bin/appearance-dispatch`, not by the plugin. Set it via `env` in your watcher (e.g. WezTerm) — not here. See [Connecting it to your terminal](#connecting-it-to-your-terminal-the-watcher).

</details>

For `my_immediate_callback`, see [If you want your shell to react](#if-you-want-your-shell-to-react).

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

The plugin gives you three hooks. The right one depends on what you are trying to do.

| Hook | Runs | Use for |
|---|---|---|
| `ZAC_IO_CMD` | Once, in the dispatcher, before shells are signaled | Writing config files to disk |
| `ZAC_IMMEDIATE_CALLBACK_FNC` | In every shell, immediately on signal | Updating env vars and shell settings |
| `ZAC_DEFERRED_CALLBACK_FNC` | In every shell, at the next prompt | Prompt redraws, anything heavier |

**`ZAC_IO_CMD`** is an executable path, not a shell function. The dispatcher runs it once per appearance change (under a lock, idempotent) before signaling any shell. Use it for anything that writes to files on disk: tool config files, theme files, JSON settings. By the time shells receive the signal, the files are already updated. If it exits with a non-zero status the entire pipeline is aborted — no shells are signaled.

Must be a single executable path. If you need to pass arguments or set environment variables, write a small wrapper script. Use `#!/bin/zsh` (without `-f`) as the shebang so that your `.zshenv` is sourced automatically and your usual environment variables are available.

`ZAC_IO_CMD` is read by `bin/appearance-dispatch`, not by the plugin. If your watcher is an external process that does not inherit your shell environment (such as WezTerm), you must pass `ZAC_IO_CMD` explicitly via `env` when invoking the dispatcher — exporting it in your `.zshrc` or plugin config has no effect on that invocation. See the WezTerm example below.

```zsh
export ZAC_IO_CMD=/path/to/your/io-script
```

**`ZAC_IMMEDIATE_CALLBACK_FNC`** is a shell function called directly inside the signal handler in every shell, before the next prompt redraws. Use it for lightweight, instant in-shell updates.

Allowed: `export`, `typeset`, `zstyle`, and `source` of files that only contain variable assignments.
Not allowed: I/O, subshells, pipes, or external commands — these can hang or corrupt shell state inside a signal handler.

```zsh
my_immediate_callback() {
  local is_dark=$1

  if (( is_dark )); then
    export FZF_DEFAULT_OPTS='--color=bg+:#1f2430,fg:#c8d3f5,hl:#82aaff'
  else
    export FZF_DEFAULT_OPTS='--color=bg+:#f2f2f2,fg:#2d2a2e,hl:#005f87'
  fi
}

export ZAC_IMMEDIATE_CALLBACK_FNC=my_immediate_callback
```

**`ZAC_DEFERRED_CALLBACK_FNC`** is a shell function called at the next `precmd`/`preexec` boundary in every shell. Safe for anything: prompt redraws, plugin reconfiguration, external tool calls. Use it when you need to do something heavier in-shell that can wait until the next prompt.

```zsh
my_deferred_callback() {
  local is_dark=$1
  # safe to call external tools, redraw prompt, etc.
}

export ZAC_DEFERRED_CALLBACK_FNC=my_deferred_callback
```

## Connecting it to your terminal (the “watcher”)

The plugin does not try to guess when your system appearance changes.
Instead, you (or your terminal) call a tiny helper script when the appearance changes.

This repo ships a standalone dispatcher: `bin/appearance-dispatch`.

### Recommended: `dispatch`

```
bin/appearance-dispatch dispatch <on|off|1|0|true|false>
```

This is the unified pipeline. On each call it:

1. Runs `ZAC_IO_CMD` once if the appearance changed (skipped if already applied — idempotent).
2. Writes both ground truths: tmux `@dark_appearance` and the cache file.
3. Signals all registered shells with `USR1`.

If `ZAC_IO_CMD` fails, the entire pipeline is aborted — no shells are signaled. This ensures your tool config files and your shells are always in sync.

To pass `ZAC_IO_CMD` from a watcher that does not inherit your shell environment (such as WezTerm), set it via `env`:

```
env ZAC_IO_CMD=/path/to/your/io-script bin/appearance-dispatch dispatch 1
```

### Legacy: `tmux` and `cache`

The older two-call pattern is still supported for backward compatibility:

```
bin/appearance-dispatch tmux <on|off|1|0|true|false>
bin/appearance-dispatch cache <on|off|1|0|true|false>
```

Both now call the same unified pipeline internally, so they behave identically to `dispatch`.

The dispatcher only signals shell processes that have opted in (shells that loaded this plugin), so it avoids accidentally sending signals to unrelated shells.

<details>
<summary><strong>TL;DR: cache updates (in-place vs atomic)</strong></summary>

The appearance cache file is updated “in place” by default. In plain words: we overwrite the contents of the same file, so it stays the same file on disk. This keeps file watchers simple.

If you set `ZAC_CACHE_ATOMIC=1`, updates become “atomic”: the dispatcher writes a temporary file and then swaps it into place. This is more crash-proof, but given the tiny size of the `0/1` flag a read/write race is extremely unlikely. Choose atomic mode if you want peace of mind that shell scripts always read a valid value.

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

- `ZAC_IMMEDIATE_CALLBACK_FNC` name of a function called inside the signal handler (env var assignments only)
- `ZAC_DEFERRED_CALLBACK_FNC` name of a function called at the next precmd/preexec (safe for anything)
- `ZAC_IO_CMD` path to an executable run once per appearance change by the dispatcher (heavy I/O)
- `ZAC_CACHE_DIR` where to store the non-tmux cache file and pid registry
- `ZAC_LINUX_DESKTOP` set to `gnome` to force GNOME support, or `none` to disable it
- `ZAC_DEBUG` set to `1` to enable debug logging
- `ZAC_ENABLE_SSH_TMUX` set to `0` to disable the `ssh-tmux` extra

`ZAC_CALLBACK_FNC` is accepted as a legacy alias for `ZAC_DEFERRED_CALLBACK_FNC`.

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

local function scheme_for_appearance(appearance)
  local zac_dispatcher = home .. '/path/to/zsh-appearance-control/bin/appearance-dispatch'

  -- WezTerm is a GUI app and does not inherit the login-shell PATH.
  -- Tools called by appearance-dispatch (such as tmux) may not be found
  -- unless you explicitly extend PATH here.
  -- Common directories to add:
  --   macOS Homebrew (Apple Silicon): /opt/homebrew/bin
  --   macOS Homebrew (Intel):         /usr/local/bin
  --   zinit polaris:                  home .. '/.local/share/zinit/polaris/bin'
  local tmux_dir = '/opt/homebrew/bin'  -- adjust to match where tmux lives on your system
  local env_path = tmux_dir .. ':' .. os.getenv('PATH')

  local is_dark = appearance:find('Dark') ~= nil
  local dark = is_dark and '1' or '0'

  -- Single dispatch call: writes both ground truths and signals all shells.
  -- Pass ZAC_IO_CMD explicitly — WezTerm does not inherit your shell environment,
  -- so env vars from .zshenv are not available here.
  -- Omit the ZAC_IO_CMD line if you have no heavy I/O to run.
  wezterm.run_child_process({
    'env',
    'PATH=' .. env_path,
    'ZAC_IO_CMD=' .. home .. '/path/to/your/io-script',  -- optional
    zac_dispatcher, 'dispatch', dark,
  })

  return is_dark and 'My Dark Scheme' or 'My Light Scheme'
end

wezterm.on('window-config-reloaded', function(window, pane)
  local overrides = window:get_config_overrides() or {}
  overrides.color_scheme = scheme_for_appearance(window:get_appearance())
  window:set_config_overrides(overrides)
end)
```

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

Your watcher updates it by calling `bin/appearance-dispatch dispatch ...`, and then your shells (and Neovim) can react.

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

Now, whenever your watcher updates `ZAC_CACHE_DIR/appearance` (via `bin/appearance-dispatch dispatch ...`), Emacs can follow along.

## Author
- **Author:** Andrea Alberti
- **GitHub Profile:** [alberti42](https://github.com/alberti42)
- **Donations:** [![Buy Me a Coffee](https://img.shields.io/badge/Donate-Buy%20Me%20a%20Coffee-orange)](https://buymeacoffee.com/alberti)

Feel free to contribute to the development of this plugin or report any issues in the [GitHub repository](https://github.com/alberti42/zsh-appearance-control/issues).

## License

This project is licensed under the MIT License. See the [LICENSE](LICENSE) file for details.
