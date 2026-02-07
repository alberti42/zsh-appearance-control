# zsh-appearance-control

`zsh-appearance-control` is a small Zsh plugin that helps your shell “remember” whether you are in light mode or dark mode.

If you use a theme, prompt, or other plugins that should look different in dark mode, this plugin gives you a simple, reliable switch you can build on.

It’s designed to be calm and predictable:

- it does not constantly poll your system
- it does not run heavy commands every time your prompt is drawn
- it updates when something tells it “the appearance changed”

## How it works (in plain words)

Your terminal (or a tiny helper you run) notices when the system appearance changes.
It then nudges your shells.

Inside each shell, the plugin keeps a small cached value (`0` or `1`) and runs your callback (optional) to update your prompt.

There are two “places” the plugin can read from:

- If you are inside tmux, tmux option `@dark_appearance` is the source of truth.
- If you are not inside tmux, a small cache file is used (in your user cache directory).

## Install

Install it with your plugin manager the same way you install other Zsh plugins.

After installation, restart your terminal or reload your shell.

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

### If you want your prompt to react

You can provide a callback function name via an environment variable.
When the cached value changes, the plugin will call your function with one argument:

- `1` for dark
- `0` for light

Example idea (keep it simple): export a few variables your theme reads.

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
It connects over SSH and makes sure the remote tmux session has `@dark_appearance` set.

You can disable it by setting:

```zsh
export ZAC_ENABLE_SSH_TMUX=0
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
