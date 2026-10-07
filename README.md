# macOS (Apple silicon) — dotfiles

Work machine. zsh with powerlevel10k, AeroSpace for tiling, Alacritty as the
terminal, Neovim as the editor. Every top-level directory is a
[GNU stow](https://www.gnu.org/software/stow/) package that mirrors `$HOME`;
files go where each tool looks by default (`~/.zshrc`, `~/.gitconfig`,
`~/.config/nvim`, …), nothing relocates them.

## 1. Homebrew packages

```sh
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
xcode-select --install          # C compiler for nvim-treesitter parsers
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

stow refuses to replace an existing file; on a machine with an older setup, see
[Replacing an existing setup](#replacing-an-existing-setup).

| Package | Provides |
|---|---|
| `zsh` | `.zprofile` is the environment (PATH, nvm, coursier's JDK, `EDITOR`); `.zshrc` is interactive only; `.p10k.zsh` |
| `git` | delta pager, diff3 conflicts, LFS filter, `gh` as GitHub credential helper; global ignore |
| `ssh` | `~/.ssh/config` only — never a key. Includes `~/.famlydev/ssh_config`, written by the Famly dev tooling |
| `gh` | `config.yml` only; `hosts.yml` holds the token and stays out |
| `aerospace` | i3-style tiling; starts `borders` |
| `herdr` | agent multiplexer, prefix ctrl+space |
| `tmux` | prefix ctrl+space, vi copy mode into `pbcopy`; no alt bindings, AeroSpace owns alt |
| `bin` | `scalafmt` wrapper that fetches the version pinned in the project's `.scalafmt.conf` |
| the rest | app configs; comments in the files say why |

No `~/.zshenv`: nothing needs to run in every zsh, scripts included. PATH is in
`.zprofile`, not `.zshenv`, because macOS's `/etc/zprofile` runs `path_helper`
after `.zshenv` and would push those entries behind the system paths.

## 3. Runtimes and tools outside Homebrew

```sh
# node — nvm, into ~/.config/nvm (NVM_DIR in .zprofile)
export NVM_DIR="$HOME/.config/nvm" && mkdir -p "$NVM_DIR"
PROFILE=/dev/null bash -c 'curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/HEAD/install.sh | bash'
nvm install --lts

# composer → ~/.local/bin/composer
php -r "copy('https://getcomposer.org/installer', 'composer-setup.php');"
php composer-setup.php --install-dir="$HOME/.local/bin" --filename=composer && rm composer-setup.php

# java and Scala tools — coursier (from the Brewfile)
cs java --jvm zulu:25 -version   # downloads the JDK that .zprofile puts on PATH
cs install sbt scalafix

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

`PROFILE=/dev/null` keeps the nvm installer from appending to the shell files,
which are symlinks into this repo; the lines it needs are already there. Docker Desktop: Settings → Advanced → CLI tools in
the *System* location (`/usr/local/bin`), for the same reason.

Then in nvim: plugins install on first start (`vim.pack`), then `:MetalsInstall`.

## 4. Shell notes

- Order in `.zshrc` matters: direnv around the powerlevel10k instant prompt;
  aliases and zoxide at the very end, because zsh expands aliases while parsing
  and `alias cd=z` would otherwise leak into nvm's functions.
- nvm and coursier's JDK are set up in `.zprofile`, so node and java are on PATH
  for non-interactive processes too. nvm is sourced again in `.zshrc` only when
  its function is missing — nested shells inherit PATH but not functions.
- fzf key bindings go through `zvm_after_init_commands`: zsh-vi-mode resets
  keybindings when it initialises.
- Python: uv only (`uv.toml` refuses Homebrew's Python).

## 5. Maintenance

```sh
brew update && brew upgrade          # zsh plugins included
brew bundle dump --file=Brewfile --force --no-vscode   # after installing something new
```

## Replacing an existing setup

Everything below is moved, not deleted, into one backup folder.

**1. Install packages while the old shell still works**

```sh
cd ~/Projects/dotfiles-mac && git pull
brew bundle --file=Brewfile
cs java --jvm zulu:25 -version && cs install sbt scalafix
```

**2. Back up and clear every path stow will own, plus dead shell files**

```sh
B=~/dotfiles-backup-$(date +%Y%m%d-%H%M%S); mkdir -p "$B"
for p in .zshenv .zprofile .zshrc .p10k.zsh .profile .config/zsh \
         .gitconfig .config/git .ssh/config .config/gh/config.yml \
         .config/aerospace .config/alacritty .config/kitty .config/lazygit \
         .config/nvim .config/lf .config/uv .config/tmux .config/herdr/config.toml \
         .local/bin/scalafmt; do
  [ -e ~/$p ] || [ -L ~/$p ] || continue
  mkdir -p "$B/$(dirname $p)" && mv ~/$p "$B/$p"
done
ls -A "$B" "$B/.config"
```

`~/.config/gh/hosts.yml` (token), `~/.ssh` keys and `~/.config/nvm` stay put.

**3. Restore shell history, then stow**

```sh
cp "$B/.config/zsh/.zsh_history" ~/.zsh_history 2>/dev/null
mkdir -p ~/.ssh ~/.local/bin ~/.config/gh ~/.config/herdr   # see §2
cd ~/Projects/dotfiles-mac && stow */
```

**4. Check, in a new terminal tab (keep the old one open)**

```sh
echo $EDITOR                          # nvim
whence -w nvm z lf                    # functions
command -v node java cs claude composer docker tmux herdr
jq '{theme, editorMode, disableAgentView}' ~/.claude/settings.json
git config --get core.pager           # delta
ssh -G github.com | grep -i identityfile
zsh -lc 'command -v node java'        # non-interactive login shell has them too
```

**5. Finish up**

- `aerospace reload-config`
- open nvim (plugins install), then `:MetalsInstall`
- the Claude Code settings merge and the `herdr integration` line from §3
- Docker Desktop: Settings → Advanced → CLI tools in the *System* location, so
  it stops writing to the shell files

**6. Remove what this setup no longer uses**, once the checks pass

```sh
rm -rf ~/.sdkman ~/.deno               # java and sbt come from coursier
rm -rf ~/.config/gcloud                # gcloud config and credentials
rm -rf ~/.config/.wrangler ~/.config/cagent ~/.cagent ~/.mastra ~/.g8
```

**Undo:** `cd ~/Projects/dotfiles-mac && stow -D */`, then move the files in
`$B` back. Step 6 is not undoable. When everything works, `rm -rf "$B"`.
