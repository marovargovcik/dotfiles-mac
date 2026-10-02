# macOS (Apple silicon) — dotfiles

Work machine. zsh with powerlevel10k, AeroSpace for tiling, Alacritty as the
terminal, Neovim as the editor. Everything is a [GNU stow](https://www.gnu.org/software/stow/)
package: each top-level directory mirrors `$HOME`.

## 1. Homebrew packages

```sh
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
xcode-select --install          # C compiler for nvim-treesitter parsers
brew bundle --file=Brewfile
```

Not from Homebrew: Alacritty and 1Password (vendor `.dmg`s into `/Applications`).

## 2. Dotfiles (stow)

```sh
git clone --recurse-submodules git@github.com:marovargovcik/dotfiles-mac.git ~/Projects/dotfiles-mac
mkdir -p ~/.ssh ~/.local/bin ~/.local/share ~/.config/zsh ~/.config/git ~/.config/gh
chmod 700 ~/.ssh
cd ~/Projects/dotfiles-mac && stow */
```

**Create the real directories first** — stow symlinks any missing directory
whole, and shell history, SSH keys, `gh` tokens (`~/.config/gh/hosts.yml`) and
binaries would then live inside the repo.

stow refuses to replace existing files. On a machine that already has them,
move them aside first and diff afterwards:

```sh
for f in ~/.zshenv ~/.zprofile ~/.config/zsh/.zshrc ~/.config/zsh/.p10k.zsh \
         ~/.gitconfig ~/.config/git/ignore ~/.ssh/config ~/.config/gh/config.yml \
         ~/.config/aerospace/aerospace.toml ~/.config/alacritty/alacritty.toml \
         ~/.config/kitty/kitty.conf ~/.local/bin/scalafmt; do
  [ -e "$f" ] && [ ! -L "$f" ] && mv "$f" "$f.pre-stow"
done
[ -d ~/.config/zsh/plugins ] && [ ! -L ~/.config/zsh/plugins ] && mv ~/.config/zsh/plugins ~/.config/zsh/plugins.pre-stow
```

What the packages provide:

| Package | Provides |
|---|---|
| `zsh` | `~/.zshenv` moves zsh config to `~/.config/zsh` (`ZDOTDIR`); `.zshrc`, `.p10k.zsh`, and the plugins as git submodules |
| `git` | delta pager, diff3 conflicts, LFS filter, `gh` as GitHub credential helper; global ignore |
| `ssh` | `~/.ssh/config` only — never a key. Includes `~/.famlydev/ssh_config`, written by the Famly dev tooling |
| `gh` | `config.yml` only; `hosts.yml` holds the token and stays out |
| `aerospace` | i3-style tiling; starts `borders` |
| `bin` | `scalafmt` wrapper that fetches the version pinned in the project's `.scalafmt.conf` |
| the rest | app configs; comments in the files say why |

## 3. Runtimes and tools outside Homebrew

```sh
# node — nvm, into ~/.config/nvm (NVM_DIR is set in .zshrc)
PROFILE=/dev/null bash -c 'curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/HEAD/install.sh | bash'
nvm install --lts

# java — sdkman
curl -s "https://get.sdkman.io?rcupdate=false" | bash
sdk install java

# deno
curl -fsSL https://deno.land/install.sh | sh -s -- --no-modify-path

# composer → ~/.local/bin/composer
php -r "copy('https://getcomposer.org/installer', 'composer-setup.php');"
php composer-setup.php --install-dir="$HOME/.local/bin" --filename=composer && rm composer-setup.php

# Scala tools (coursier from the Brewfile)
cs install sbt scalafix

# claude → ~/.local/bin/claude
curl -fsSL https://claude.ai/install.sh | bash

git lfs install --skip-repo
gh auth login
```

`rcupdate=false`, `--no-modify-path` and `PROFILE=/dev/null` keep installers
from appending to `.zshrc`; the lines they need are already there.

Then in nvim: plugins install on first start (`vim.pack`), then `:MetalsInstall`.

## 4. Shell notes

- Order in `.zshrc` matters: direnv around the powerlevel10k instant prompt;
  aliases and zoxide at the very end, because zsh expands aliases while parsing
  and `alias cd=z` would otherwise leak into nvm's and sdkman's functions.
- fzf key bindings go through `zvm_after_init_commands`: zsh-vi-mode resets
  keybindings when it initialises.
- Python: uv only (`uv.toml` refuses Homebrew's Python).

## 5. Maintenance

```sh
brew update && brew upgrade
git submodule update --remote          # zsh plugins
brew bundle dump --file=Brewfile --force --no-vscode   # after installing something new
```
