#!/usr/bin/env bats
# tt switch: agent panes from Claude Code to Codex and back, each agent on its own conversation in the pane.

# shellcheck source=helpers.bash
source "$BATS_TEST_DIRNAME/helpers.bash"

setup() {
    setup_tt
    git_repo app
    "$tt" new task </dev/null
    task=$(pane_of "$TT_WORKTREES/app/task")
    orch=$(tmux display -p -t app:0 '#{pane_id}')
    path=$TT_WORKTREES/app/task
}

teardown() {
    teardown_tt
}

@test "with no agent given, switch says what new panes start" {
    run "$tt" switch
    assert_output claude
}

@test "every claude pane goes over to codex in its directory, pointed at Claude's conversation; new panes start codex" {
    agent_in "$orch"
    agent_in "$task"
    run "$tt" switch codex </dev/null
    assert_success
    assert_line "$orch: claude → codex"
    assert_line "$task: claude → codex"
    eventually prompted codex "$path" "moved this pane from Claude Code to you"
    prompted codex "$path" "$tmp/t/claude-${task#%}"
    prompted codex "$tmp/app" "$tmp/t/claude-${orch#%}"
    run "$tt" switch
    assert_output codex
    "$tt" new other </dev/null
    eventually codex_ran "$TT_WORKTREES/app/other" ''
}

@test "the prompt's command prints the end of the conversation, messages only" {
    agent_in "$task"
    transcript=$tmp/claude.jsonl
    tmux set -p -t "$task" @agent_transcript_claude "$transcript"
    cat >"$transcript" <<'EOF'
{"type": "user", "timestamp": "2026-01-01T10:00:00Z", "message": {"content": "fix the login"}}
{"type": "assistant", "timestamp": "2026-01-01T10:00:01Z", "message": {"content": [{"type": "text", "text": "On it."}, {"type": "tool_use", "name": "Bash"}]}}
{"type": "user", "timestamp": "2026-01-01T10:00:02Z", "message": {"content": [{"type": "tool_result", "content": "huge"}]}}
{"type": "attachment", "timestamp": "2026-01-01T10:00:03Z"}
EOF
    "$tt" switch codex "$task"
    eventually prompted codex "$path" "jq -c"
    cmd=$(grep -o "jq -c .* | tail -n 40" "$tmp/codex.log")
    run bash -c "$cmd"
    assert_output '["2026-01-01T10:00:00Z","user","fix the login"]
["2026-01-01T10:00:01Z","assistant","On it."]'
}

@test "back on claude, it resumes its own conversation and reads Codex's from the switch on" {
    agent_in "$task"
    "$tt" switch codex "$task"
    agent_in "$task" "" codex
    switched=$(tag "$task" @agent_switched)
    run "$tt" switch claude "$task"
    assert_output "$task: codex → claude"
    eventually prompted claude "$path" "--resume claude-${task#%} tt switch moved this pane from Codex to you"
    prompted claude "$path" "$tmp/t/codex-${task#%}"
    prompted claude "$path" "--arg since $switched"
    agent_in "$task"
    "$tt" switch codex "$task"
    eventually prompted codex "$path" "resume codex-${task#%} tt switch"
}

@test "a conversation that never got a prompt, and so has no transcript, isn't resumed" {
    agent_in "$task"
    "$tt" switch codex "$task"
    agent_in "$task" "" codex
    rm "$tmp/t/claude-${task#%}"
    "$tt" switch claude "$task"
    eventually prompted claude "$path" "tt switch moved this pane from Codex to you"
    run prompted claude "$path" "--resume"
    assert_failure
}

@test "one pane goes alone: the others and what new panes start stay" {
    agent_in "$orch"
    agent_in "$task"
    run "$tt" switch codex "$task"
    assert_output "$task: claude → codex"
    eventually runs "$task" codex
    assert runs "$orch" claude
    run "$tt" switch
    assert_output claude
}

@test "panes on the agent already stay" {
    agent_in "$orch"
    agent_in "$task"
    "$tt" switch codex "$task"
    agent_in "$task" "" codex
    run "$tt" switch codex
    assert_output "$orch: claude → codex"
    run "$tt" switch codex "$task"
    assert_output "$task: on codex already"
}

@test "a working agent stays unless --force" {
    agent_in "$task" working
    run "$tt" switch codex </dev/null
    assert_failure
    assert_output "$task app:task is working
tt: left as they are; --force switches them too"
    assert runs "$task" claude
    run "$tt" switch --force codex </dev/null
    assert_output "$task: claude → codex"
}

@test "a blocked agent's question goes along" {
    agent_in "$task" blocked
    tmux send-keys -t "$task" 'Allow git push? (y/n)' Enter
    eventually shows "$task" 'Allow git push?'
    "$tt" switch codex "$task"
    eventually prompted codex "$path" "Claude Code was waiting on its person for this; ask them again:"
    prompted codex "$path" "Allow git push? (y/n)"
}

@test "a pane with no agent is refused" {
    shell=$(tmux new-window -d -P -F '#{pane_id}' -t keep:)
    run "$tt" switch codex "$shell"
    assert_failure
    assert_output "tt: $shell runs no agent"
}

@test "the menu: this pane or all of them, what changes nothing greyed out" {
    real=$(command -v tmux)
    # shellcheck disable=SC2016 # expanded by the stub
    stub tmux '[ "$1" = display-menu ] && { printf "%s\n" "$@" >"'"$tmp"'/menu"; exit; }
exec '"$real"' "$@"'
    agent_in "$orch"
    agent_in "$task"
    "$tt" switch --menu "$task" client
    run grep -e → "$tmp/menu"
    assert_output "-this pane → claude
this pane → codex
-all panes → claude
all panes → codex (2)"
    grep -qxF "run-shell -b \"$tt switch --force codex $task >/dev/null\"" "$tmp/menu"
}
