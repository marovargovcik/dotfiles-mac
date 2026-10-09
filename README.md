# macOS (Apple silicon) — dotfiles

Work machine. zsh with powerlevel10k, AeroSpace for tiling, Alacritty as the
terminal, Neovim as the editor. Every top-level directory is a
[GNU stow](https://www.gnu.org/software/stow/) package that mirrors `$HOME`;
files go where each tool looks by default (`~/.zshrc`, `~/.gitconfig`,
`~/.config/nvim`, …), nothing relocates them.

## 1. Node, then Homebrew packages

```sh
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
eval "$(/opt/homebrew/bin/brew shellenv)"
xcode-select --install          # git for nvm; C compiler for nvim-treesitter parsers

# node — nvm, into ~/.config/nvm (NVM_DIR in .zprofile), and its globals
export NVM_DIR="$HOME/.config/nvm" && mkdir -p "$NVM_DIR"
PROFILE=/dev/null bash -c 'curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/HEAD/install.sh | bash'
. "$NVM_DIR/nvm.sh" && nvm install --lts
npm install -g corepack yarn typescript-language-server typescript

brew bundle --file=Brewfile
```

Not from Homebrew: Alacritty and 1Password (vendor `.dmg`s into `/Applications`).

## 2. Dotfiles (stow)

```sh
git clone git@github.com:marovargovcik/dotfiles-mac.git ~/Projects/dotfiles-mac
mkdir -p ~/.ssh ~/.local/bin ~/.config/gh ~/.config/herdr && chmod 700 ~/.ssh
cd ~/Projects/dotfiles-mac && stow */
```

**Create those directories first** — stow symlinks any missing directory whole,
and SSH keys, the `gh` token (`~/.config/gh/hosts.yml`), binaries in
`~/.local/bin` and herdr's plugins, sockets and logs would then live inside the
repo.

`.stowrc` sets the target to `~`: stow's default is the repo's parent
directory, here `~/Projects`. It is read only when stow runs from the repo.

| Package | Provides |
|---|---|
| `zsh` | `.zprofile` is the environment (PATH, nvm, coursier's JDK, `EDITOR`); `.zshrc` is interactive only; `.p10k.zsh` |
| `git` | delta pager, diff3 conflicts, LFS filter, `gh` as GitHub credential helper; global ignore |
| `ssh` | `~/.ssh/config` only — never a key. Includes `~/.famlydev/ssh_config`, written by the Famly dev tooling |
| `gh` | `config.yml` only; `hosts.yml` holds the token and stays out |
| `aerospace` | i3-style tiling; starts `borders` |
| `herdr` | agent multiplexer, prefix ctrl+space |
| `tmux` | prefix ctrl+space, vi copy mode into `pbcopy`; no alt bindings, AeroSpace owns alt |
| the rest | app configs; comments in the files say why |

No `~/.zshenv`: nothing needs to run in every zsh, scripts included. PATH is in
`.zprofile`, not `.zshenv`, because macOS's `/etc/zprofile` runs `path_helper`
after `.zshenv` and would push those entries behind the system paths.

## 3. Runtimes and tools outside Homebrew

```sh
# composer → ~/.local/bin/composer
php -r "copy('https://getcomposer.org/installer', 'composer-setup.php');"
php composer-setup.php --install-dir="$HOME/.local/bin" --filename=composer && rm composer-setup.php

# coursier → ~/Library/Application Support/Coursier/bin (on PATH in .zprofile),
# then the JDK .zprofile puts on PATH, and the Scala tools
curl -fL https://github.com/coursier/coursier/releases/latest/download/cs-aarch64-apple-darwin.gz | gzip -d > /tmp/cs
chmod +x /tmp/cs && /tmp/cs install cs && rm /tmp/cs
cs java --jvm zulu:25 -version
cs install sbt scalafix scalafmt

# Python language server for nvim
uv tool install basedpyright

# claude → ~/.local/bin/claude
curl -fsSL https://claude.ai/install.sh | bash

# Claude Code preferences, merged into ~/.claude/settings.json. Not a stow
# package: on this machine the file also holds the organization's plugins and
# permissions, which stay out of the repo.
f=~/.claude/settings.json; mkdir -p ~/.claude; [ -s "$f" ] || echo '{}' > "$f"
jq '. + {theme: "dark", editorMode: "vim", disableAgentView: true}' "$f" > "$f.new" && mv "$f.new" "$f"

herdr integration install claude   # agent state in the herdr sidebar

git lfs install --skip-repo
gh auth login
```

`PROFILE=/dev/null` (§1) keeps the nvm installer from appending to the shell files,
which are symlinks into this repo; the lines it needs are already there. Docker Desktop: Settings → Advanced → CLI tools in
the *System* location (`/usr/local/bin`), for the same reason.

Then in nvim: plugins install on first start (`vim.pack`), then `:MetalsInstall`.

## 4. Shell notes

- Order in `.zshrc` matters: aliases and zoxide at the very end, because zsh
  expands aliases while parsing and `alias cd=z` would otherwise leak into
  nvm's functions.
- nvm and coursier's JDK are set up in `.zprofile`, so node and java are on PATH
  for non-interactive processes too. nvm is sourced again in `.zshrc` only when
  its function is missing — nested shells inherit PATH but not functions.
- fzf key bindings go through `zvm_after_init_commands`: zsh-vi-mode resets
  keybindings when it initialises.
- Python: uv only (`uv.toml` refuses Homebrew's Python).

## 5. Maintenance

```sh
brew update && brew upgrade          # zsh plugins included
brew bundle dump --file=Brewfile --force --no-vscode --no-npm   # after installing something new
uv tool upgrade --all && npm update -g && cs update
```

npm globals belong to one Node version: install a new one with
`nvm install --lts --reinstall-packages-from=current` to keep them.

