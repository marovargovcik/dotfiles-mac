# Login environment: everything a process started from this login needs,
# interactive or not (nvim jobs, scripts, editors reading the login env).
# Not .zshenv: macOS's /etc/zprofile runs path_helper after it and would push
# these entries behind the system paths.

export EDITOR=nvim
export VISUAL=nvim

# home-brew
eval "$(/opt/homebrew/bin/brew shellenv)"

# php (brew keg)
export PATH="/opt/homebrew/opt/php@8.4/bin:$PATH"
export PATH="/opt/homebrew/opt/php@8.4/sbin:$PATH"

# mysql (brew keg)
export PATH="/opt/homebrew/opt/mysql-client/bin:$PATH"

# coursier (cs install sbt scalafix)
export PATH="$PATH:$HOME/Library/Application Support/Coursier/bin"

# user executables
export PATH="$HOME/.local/bin:$PATH"

# nvm: sourced here so the default node is on PATH for non-interactive use too;
# .zshrc re-sources it in nested shells, which inherit PATH but not the function.
export NVM_DIR="$HOME/.config/nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"

ssh-add --apple-load-keychain 2>/dev/null

# java: coursier's JDK sets JAVA_HOME and goes first on PATH (keep last)
command -v cs >/dev/null && eval "$(cs java --jvm zulu:25 --env)"
