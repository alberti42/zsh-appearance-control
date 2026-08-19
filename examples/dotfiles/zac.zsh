#!/hint/zsh

# EXAMPLE — not a drop-in.
#
# Snapshot of the author's private dotfiles (zinit/src/zac/zac.zsh), taken
# 2026-08-19. It is kept
# here because a real configuration is more instructive than a synthetic one, and
# it is NOT refreshed automatically: treat it as a worked example, not as the
# current state of anyone's setup.
#
# What it demonstrates
#   - loading the plugin with zinit, turbo mode, and priming the state at load
#     time (`zac sync && __my_appearance_immediate "$REPLY"`), so the very first
#     prompt is already themed;
#   - a ZAC_IMMEDIATE_CALLBACK_FNC that obeys the contract: variable assignments
#     and zstyle only — no subshells, no external commands, no output. It runs
#     inside TRAPUSR1, where anything heavier can wedge the shell.
#
# It depends on things that exist only in that setup, and that you are expected
# to replace: $LS_COLORS_FILES and $FZF_DEFAULT_OPTS_CATPPUCCIN (associative
# arrays built by sibling snippets for vivid and fzf), $FSH_CACHE_FILES,
# the zsh-opencode-tab plugin, $DOTFILES_DIR, and zinit's +zi-log.

function __my_appearance_immediate() {
  local is_dark=$1

  # Prevent execution if called without argument
  [[ $is_dark == (0|1) ]] || return

  if (( is_dark )); then
    local BACKGROUND_COLOR="#303446"

    # LS_COLORS
    IFS= read -r LS_COLORS < "$LS_COLORS_FILES[dark]" && export LS_COLORS

    # fzf plugin
    export FZF_DEFAULT_OPTS="$FZF_DEFAULT_OPTS_CATPPUCCIN[frappe]"

    # bat
    export BAT_CONFIG_PATH="$DOTFILES_DIR/.config/bat/config-dark"

    # fast-syntax-highlighting
    #source "$FSH_CACHE_FILES[dark]"

    # ZLE customization
    typeset -ga zle_highlight=('paste:fg=#00E5FF,bg=#002B36')
  else
    local BACKGROUND_COLOR="#EFF1F5"

    # LS_COLORS
    IFS= read -r LS_COLORS < "$LS_COLORS_FILES[light]" && export LS_COLORS

    # fzf plugin
    export FZF_DEFAULT_OPTS="$FZF_DEFAULT_OPTS_CATPPUCCIN[latte]"

    # bat
    export BAT_CONFIG_PATH="$DOTFILES_DIR/.config/bat/config-light"

    # fast-syntax-highlighting
    #source "$FSH_CACHE_FILES[light]"

    # ZLE customization
    typeset -ga zle_highlight=('paste:fg=#00B3FF,bg=#DDECF9')
  fi

  # zsh-opencode-tab plugin
  if (( ${+_zsh_opencode_tab} )); then
    _zsh_opencode_tab[spinner.bg_hex]=$BACKGROUND_COLOR
  else
    export Z_OC_TAB_SPINNER_BG_HEX=$BACKGROUND_COLOR
  fi

  # Check if LS_COLORS is defined
  if (( ${+LS_COLORS} )); then
    # General completion colors
    zstyle ':completion:*' list-colors "${(s.:.)LS_COLORS}"

    # Default list colors + highlight the matched substring/item with gray-blue background, normal foreground
    # This configuration is only relevant for `menu select` and not relevant for fzf-tab
    zstyle ':completion:*:default' list-colors \
      "${(s.:.)LS_COLORS}" \
      'ma=48;2;60;70;90'
  else
    [[ ${ZINIT[MUTE_WARNINGS]} != (1|true|on|yes) && $quiet != -q ]] && \
      +zi-log "{u-warn}Warning{b-warn}: zsh-completions cannot use LS_COLORS."
  fi
}

() {
  local __local_plugin_path="$DOTFILES_DIR/oh-my-zsh/custom/plugins"
  zinit lucid wait light-mode for \
      wait'0' \
      atinit"export ZAC_IMMEDIATE_CALLBACK_FNC=__my_appearance_immediate" \
      atload'zac sync && __my_appearance_immediate "$REPLY"' \
      $__local_plugin_path/zsh-appearance-control
}
