#!/usr/bin/env bats
# tt pick's rows, a tree of sessions, windows and panes with the agents' states, and its preview of a row's pane.

# shellcheck source=helpers.bash
source "$BATS_TEST_DIRNAME/helpers.bash"

setup() {
    setup_tt
    git_repo app
    "$tt" new task </dev/null
    task=$(pane_of "$TT_WORKTREES/app/task")
    orch=$(tmux display -p -t app:0 '#{pane_id}')
}

teardown() {
    teardown_tt
}

# plain: stdin without its colours.
plain() { sed $'s/\033\\[[0-9;]*m//g'; }

# rule <width>: a session row's rule.
rule() { printf '─%.0s' $(seq "$1"); }

@test "a session, its windows and the panes of a split one, as a tree, each with its most urgent state" {
    agent_in "$orch" "done"
    agent_in "$task" blocked
    tmux select-pane -t "$task" -T '✳ Fix the login'
    shell=$(tmux split-window -d -P -F '#{pane_id}' -t "$task" -c "$tmp/app")
    run "$tt" _pick-rows
    assert_success
    assert_equal "$(plain <<<"$output" | tr '\t' '|')" "$(tag app session_id)| |⚠ app $(rule 37) 2 windows
$(tag app:0 window_id)|1|✓ ├─ 0 orch ◆     done     app  app:0
$(tag app:1 window_id)|2|⚠ └─ 1 task task  blocked  Fix the login  app:1
$task| |⚠    ├─ .0        blocked  Fix the login  app:1.0
$shell| |     └─ .1        bash     app  app:1.1
$(tag keep session_id)| |  keep $(rule 36) 1 window
$(tag keep:0 window_id)|3|  └─ 0 bash       bash     home  keep:0"
}

@test "windows get codes across sessions: 1-9, then a, a1, a2" {
    for _ in $(seq 9); do tmux new-window -d -t keep:; done
    run "$tt" _pick-rows
    assert_success
    assert_equal "$(cut -f2 <<<"$output" | tr '\n' '|')" "  |1 |2 |  |3 |4 |5 |6 |7 |8 |9 |a |a1|a2|"
}

@test "a query that is a window's code puts that window first, marked with its session, then a rule" {
    rm "$tmp/bin/fzf"
    for _ in $(seq 9); do tmux new-window -d -t keep:; done
    run "$tt" _pick-rows a1
    assert_success
    assert_equal "$(cut -f1 <<<"$output" | head -2 | tr '\n' '|')" "$(tag keep:8 window_id)|-|"
    assert_line --index 0 --partial $'\033[1m◀ a1\033[0m · keep'
}

@test "the rows a query matches come under their session's row, and a pane under its window's" {
    rm "$tmp/bin/fzf"
    shell=$(tmux split-window -d -P -F '#{pane_id}' -t "$task" -c "$tmp/app")
    run "$tt" _pick-rows orch
    assert_equal "$(cut -f1 <<<"$output" | tr '\n' '|')" "$(tag app session_id)|$(tag app:0 window_id)|"
    run "$tt" _pick-rows 1.1
    assert_equal "$(cut -f1 <<<"$output" | tr '\n' '|')" "$(tag app session_id)|$(tag app:1 window_id)|$shell|"
}

@test "a query nothing matches, and no window's code, lists nothing" {
    rm "$tmp/bin/fzf"
    run "$tt" _pick-rows qqqq
    assert_success
    assert_output ""
}

@test "the rule after the code's window goes nowhere: no preview, kill or pull request" {
    run "$tt" _preview -
    assert_success
    assert_output ""
    run "$tt" _kill row -
    assert_success
    run "$tt" _pr -
    assert_success
}

@test "a window's name is shown whole, however long" {
    tmux rename-window -t app:1 admin/ove-171-ban-the-syntactic-scala-style-rules-with
    run "$tt" _pick-rows
    assert_success
    plain <<<"$output" | grep -q '└─ 1 admin/ove-171-ban-the-syntactic-scala-style-rules-with task '
}

@test "the icons: red blocked, green done and not looked at, yellow working, dim done and seen" {
    agent_in "$task" working
    run "$tt" _pick-rows
    assert_line --index 2 --partial $'\t\033[33m…\033[0m └─ 1'
    TMUX_PANE=$task "$tt" state "done" <<<"{\"session_id\": \"session-${task#%}\"}"
    run "$tt" _pick-rows
    assert_line --index 2 --partial $'\t\033[32m✓\033[0m └─ 1'
    tmux set -p -t "$task" @agent_seen 1
    run "$tt" _pick-rows
    assert_line --index 2 --partial $'\t\033[2m✓\033[0m └─ 1'
}

@test "the preview of a pane is what it shows, without the blank lines below" {
    shell=$(tmux new-window -d -P -F '#{pane_id}' -t keep:)
    tmux send-keys -t "$shell" 'echo previewed' Enter
    eventually shows "$shell" previewed
    run --keep-empty-lines "$tt" _preview "$shell"
    assert_equal "${lines[-2]}" previewed
}

@test "the preview of a split window stacks its panes, each under a tag" {
    eventually runs "$task" claude
    shell=$(tmux split-window -d -P -F '#{pane_id}' -t "$task" -c "$tmp/app")
    FZF_PREVIEW_LINES=10 FZF_PREVIEW_COLUMNS=30 run --keep-empty-lines "$tt" _preview "$(tag "$task" window_id)"
    assert_equal "$(plain <<<"$output" | grep -c 'app:1')" 2
    assert_line --index 0 --partial ' app:1.0  claude  task  ◀ ac'
    assert_line --index 5 --partial ' app:1.1  bash  app '
}

@test "ctrl-o opens the pull request of the branch checked out in the row's pane" {
    # shellcheck disable=SC2016 # expanded by the stub
    stub gh 'echo "$PWD $*" >"'"$tmp"'/gh.log"'
    run "$tt" _pr "$task"
    assert_success
    eventually grep -qxF "$TT_WORKTREES/app/task pr view --web" "$tmp/gh.log"
}

@test "with no pull request, ctrl-o says so instead" {
    # shellcheck disable=SC2016 # expanded by the stub
    stub tmux 'echo "$*" >>"'"$tmp"'/tmux.log"; exec '"$(command -v tmux)"' "$@"'
    run "$tt" _pr "$task"
    assert_success
    eventually grep -qF "display-message tt: no pull request for task" "$tmp/tmux.log"
}

@test "widest counts characters, not bytes" {
    source "$BATS_TEST_DIRNAME/../.local/lib/tt/pick.sh"
    assert_equal "$(printf 'ab\n├─ cdé\n' | widest)" 6
}
