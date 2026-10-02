# Interactive shell only; PATH and other environment live in .zprofile.

# keep order of direnv and powerlevel10k
# https://github.com/romkatv/powerlevel10k/issues/702#issuecomment-626222730
emulate zsh -c "$(direnv export zsh)"

# powerlevel10k (init,theme,config)
if [[ -r "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh" ]]; then
  source "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh"
fi
source $HOMEBREW_PREFIX/share/powerlevel10k/powerlevel10k.zsh-theme
[[ ! -f ~/.p10k.zsh ]] || source ~/.p10k.zsh

emulate zsh -c "$(direnv hook zsh)"

# history
HISTSIZE=200000
SAVEHIST=200000
setopt APPEND_HISTORY HIST_IGNORE_SPACE HIST_IGNORE_DUPS EXTENDED_HISTORY

# zsh plugins
source $HOMEBREW_PREFIX/share/zsh-autosuggestions/zsh-autosuggestions.zsh
source $HOMEBREW_PREFIX/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
source $HOMEBREW_PREFIX/opt/zsh-vi-mode/share/zsh-vi-mode/zsh-vi-mode.plugin.zsh
source $HOMEBREW_PREFIX/share/zsh-history-substring-search/zsh-history-substring-search.zsh

# zsh-history-substring-search bindings
bindkey -M vicmd 'k' history-substring-search-up
bindkey -M vicmd 'j' history-substring-search-down

# fzf: zsh-vi-mode resets keybindings on its (deferred) init, so bind after it.
zvm_after_init_commands+=('source <(fzf --zsh)')

# Nested shells inherit PATH from .zprofile but not shell functions.
command -v nvm >/dev/null || { [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"; }
command -v sdk >/dev/null || { [[ -s "$SDKMAN_DIR/bin/sdkman-init.sh" ]] && source "$SDKMAN_DIR/bin/sdkman-init.sh"; }

# completions: brew's and docker-cli's
FPATH="$HOMEBREW_PREFIX/share/zsh/site-functions:$HOME/.docker/completions:$FPATH"
autoload -Uz compinit
compinit

# Aliases and zoxide after everything sourced above: zsh expands aliases while
# parsing, so an earlier `alias cd=z` or `alias cat=bat` leaks into the
# functions nvm and sdkman define.
alias ls='eza'
alias ll='eza -lh'
alias la='eza -lha'
alias lt='eza --tree'
alias cat='bat'
alias lg='lazygit'

lf() {
  local tmp="$(mktemp)"
  command lf -last-dir-path="$tmp" "$@"
  if [ -f "$tmp" ]; then
    local dir="$(command cat "$tmp")"
    rm -f "$tmp"
    [ -d "$dir" ] && [ "$dir" != "$PWD" ] && cd "$dir"
  fi
}

# zoxide last: it wraps cd, and later inits win.
eval "$(zoxide init zsh)"
alias cd='z'
