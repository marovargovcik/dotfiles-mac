# shellcheck shell=bash
# Shared by tt's tests: a tmux server and home of the test's own, throwaway repos, and stand-ins for claude, codex,
# gh and fzf on the PATH.

bats_require_minimum_version 1.5.0
bats_load_library bats-support
bats_load_library bats-assert

tt=$(realpath "$BATS_TEST_DIRNAME/../.local/bin/tt")

# setup_tt: the test's own home, state, tmux server and stubs. tt runs with no terminal on stdin, as from a hook.
setup_tt() {
    # git's hooks export GIT_DIR and the like: run from one, as lefthook runs
    # these, every git call would act on the repo being committed to.
    local var
    for var in $(compgen -e GIT_); do unset "$var"; done
    tmp=$(realpath "$BATS_TEST_TMPDIR")
    export HOME=$tmp/home
    export XDG_STATE_HOME=$HOME/.local/state XDG_CACHE_HOME=$HOME/.cache XDG_RUNTIME_DIR=$tmp/run
    export TT_WORKTREES=$tmp/worktrees TMPDIR=$tmp/tmp GIT_CONFIG_GLOBAL=$HOME/.gitconfig
    # A short path: a socket's can't be over about 100 bytes.
    TMUX_TMPDIR=$(mktemp -d /tmp/tt-test.XXXXXX)
    export TMUX_TMPDIR
    unset TMUX TMUX_PANE FZF_DEFAULT_OPTS
    mkdir -p "$HOME" "$XDG_RUNTIME_DIR" "$TMPDIR" "$tmp/bin"
    git config --global user.name Test
    git config --global user.email test@example.com
    git config --global init.defaultBranch main
    PATH=$tmp/bin:$PATH
    stub_claude
    stub_codex
    stub gh 'exit 1'
    stub_fzf
    start_tmux
}

teardown_tt() {
    tmux kill-server 2>/dev/null || true
    rm -rf "$TMUX_TMPDIR"
}

# start_tmux: a server with a plain session "keep", which tt's own tmux calls then use, its panes running bash
# without the user's startup files.
start_tmux() {
    tmux -f /dev/null new-session -d -s keep -c "$HOME" 'bash --norc --noprofile' \; set -g default-command 'bash --norc --noprofile'
}

# stub <tool> [script]: a stand-in for the tool that runs the script, such as `exit 1`.
stub() {
    printf '#!/usr/bin/env bash\n%s\n' "${2:-}" >"$tmp/bin/$1"
    chmod +x "$tmp/bin/$1"
}

# named_cat <name>: a copy of cat under that name, for a stub to exec: tmux names a pane's command after the
# executable, and macOS ignores exec -a. macOS kills a copied binary until it's signed again.
named_cat() {
    mkdir -p "$tmp/libexec"
    cp "$(command -v cat)" "$tmp/libexec/$1"
    if command -v codesign >/dev/null; then codesign -f -s - "$tmp/libexec/$1" 2>/dev/null; fi
}

# stub_claude: a claude that logs its directory and arguments (a prompt's lines joined) to $tmp/claude.log, then shows
# what's pasted into it under the name claude, which is what tmux sees the pane run.
stub_claude() {
    named_cat claude
    # shellcheck disable=SC2016 # expanded by the stub
    stub claude 'a="$*"
printf "%s\t%s\n" "$PWD" "${a//$'"'\\n'"'/ }" >>"'"$tmp"'/claude.log"
exec "'"$tmp"'/libexec/claude"'
}

# stub_codex: codex as stub_claude has claude, logging to $tmp/codex.log without the flags every codex gets.
stub_codex() {
    named_cat codex
    # shellcheck disable=SC2016 # expanded by the stub
    stub codex 'args=()
while [ $# -gt 0 ]; do
    case $1 in -s | -a | -c) shift ;; *) args+=("$1") ;; esac
    shift
done
a="${args[*]}"
printf "%s\t%s\n" "$PWD" "${a//$'"'\\n'"'/ }" >>"'"$tmp"'/codex.log"
exec "'"$tmp"'/libexec/codex"'
}

# stub_fzf: an fzf that keeps its input in $tmp/fzf.in and its arguments in $tmp/fzf.args, and picks the lines
# matching $FZF_PICK, or none (as esc does).
stub_fzf() {
    # shellcheck disable=SC2016 # expanded by the stub
    stub fzf 'cat >"'"$tmp"'/fzf.in"
printf "%s\n" "$@" >"'"$tmp"'/fzf.args"
[ -n "${FZF_PICK:-}" ] || exit 130
grep -E -- "$FZF_PICK" "'"$tmp"'/fzf.in"'
}

# provider <agent>: the agent new panes start, as tt switch sets it.
provider() {
    mkdir -p "$XDG_STATE_HOME/tt"
    echo "$1" >"$XDG_STATE_HOME/tt/provider"
}

# git_repo <name>: a repo with one commit on main, as the working directory.
git_repo() {
    mkdir -p "$tmp/$1"
    cd "$tmp/$1" || return
    git init -q
    git commit -q --allow-empty -m init
}

# eventually <command...>: retries the command for up to five seconds, for what panes do in their own time.
eventually() {
    local i
    for ((i = 0; i < 50; i++)); do
        "$@" 2>/dev/null && return 0
        sleep 0.1
    done
    "$@"
}

# shows <pane> <text>: whether the pane shows the text.
shows() { tmux capture-pane -p -J -t "$1" | grep -qF "$2"; }

# runs <pane> <program>: whether the pane runs the program, as tmux sees it.
runs() { [ "$(tag "$1" pane_current_command)" = "$2" ]; }

# empty <dir>: whether the directory has nothing in it.
empty() { [ -z "$(ls -A "$1")" ]; }

# claude_ran <dir> <arguments>: whether claude started in the directory with those arguments.
claude_ran() {
    grep -qxF "$1$(printf '\t')$2" "$tmp/claude.log" 2>/dev/null
}

# codex_ran <dir> <arguments>: whether codex started in the directory with those arguments, past its flags.
codex_ran() {
    grep -qxF "$1$(printf '\t')$2" "$tmp/codex.log" 2>/dev/null
}

# prompted <agent> <dir> <text>: whether the agent started in the directory with the text in its arguments.
prompted() {
    grep -F "$2$(printf '\t')" "$tmp/$1.log" 2>/dev/null | grep -qF -- "$3"
}

# tag <target> <option>: a tmux user option of a session, window or pane.
tag() { tmux display -p -t "$1" "#{$2}"; }

# window_of <task path>: the window of the task in that worktree.
window_of() {
    tmux list-windows -a -F '#{window_id} #{@task_path}' | awk -v p="$1" '$2 == p { print $1 }'
}

# conversation <dir> <session>: a Claude Code conversation started in the directory, as tt finds it to resume it.
conversation() {
    local dir=$HOME/.claude/projects/${1//[^A-Za-z0-9]/-}
    mkdir -p "$dir"
    touch "$dir/$2.jsonl"
}

# pane_of <task path>: the pane of the task in that worktree.
pane_of() { tmux display -p -t "$(window_of "$1")" '#{pane_id}'; }

# agent_in <pane> [state] [agent]: claude (or the agent) running in the pane, its hooks having told tt the state; start
# with none. Its session is <agent>-<pane number>, its transcript $tmp/t/<session>.
agent_in() {
    local agent=${3:-claude} sid
    sid=$agent-${1#%}
    mkdir -p "$tmp/t"
    touch "$tmp/t/$sid"
    eventually runs "$1" "$agent"
    printf '{"session_id": "%s", "transcript_path": "%s", "source": "startup"}' "$sid" "$tmp/t/$sid" |
        TMUX_PANE=$1 "$tt" state start "$agent"
    [ -z "${2:-}" ] || printf '{"session_id": "%s"}' "$sid" | TMUX_PANE=$1 "$tt" state "$2" "$agent"
}
