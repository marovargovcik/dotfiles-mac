# keep order of direnv and powerlevel10k
# https://github.com/romkatv/powerlevel10k/issues/702#issuecomment-626222730
emulate zsh -c "$(direnv export zsh)"

# powerlevel10k (init,theme,config)
if [[ -r "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh" ]]; then
  source "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh"
fi
source ~/.config/zsh/plugins/powerlevel10k/powerlevel10k.zsh-theme
[[ ! -f ~/.config/zsh/.p10k.zsh ]] || source ~/.config/zsh/.p10k.zsh

emulate zsh -c "$(direnv hook zsh)"

# history
HISTSIZE=200000
SAVEHIST=200000
setopt APPEND_HISTORY HIST_IGNORE_SPACE HIST_IGNORE_DUPS EXTENDED_HISTORY

# zsh plugins
source ~/.config/zsh/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh
source ~/.config/zsh/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
source ~/.config/zsh/plugins/zsh-vi-mode/zsh-vi-mode.plugin.zsh
source ~/.config/zsh/plugins/zsh-history-substring-search/zsh-history-substring-search.zsh

# zsh-history-substring-search bindings
bindkey -M vicmd 'k' history-substring-search-up
bindkey -M vicmd 'j' history-substring-search-down

# fzf: zsh-vi-mode resets keybindings on its (deferred) init, so bind after it.
zvm_after_init_commands+=('source <(fzf --zsh)')

# home-brew
eval "$(/opt/homebrew/bin/brew shellenv)"

# php (brew keg)
export PATH="/opt/homebrew/opt/php@8.4/bin:$PATH"
export PATH="/opt/homebrew/opt/php@8.4/sbin:$PATH"

# mysql (brew keg)
export PATH="/opt/homebrew/opt/mysql-client/bin:$PATH"

# nvm
export NVM_DIR="$HOME/.config/nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"

# docker-cli completions
FPATH="$HOME/.docker/completions:$FPATH"
autoload -Uz compinit
compinit

# deno
export PATH="$HOME/.deno/bin:$PATH"

# coursier (cs install sbt scalafix scalafmt)
export PATH="$PATH:$HOME/Library/Application Support/Coursier/bin"

# user executables
export PATH="$HOME/.local/bin:$PATH"

ssh-add --apple-load-keychain 2>/dev/null

# sdk man (keep last among PATH changes: its candidates go first)
export SDKMAN_DIR="$HOME/.sdkman"
[[ -s "$HOME/.sdkman/bin/sdkman-init.sh" ]] && source "$HOME/.sdkman/bin/sdkman-init.sh"

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
