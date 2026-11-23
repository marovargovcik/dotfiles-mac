# shellcheck shell=bash
# A pane's conversations, one per agent, and the start of an agent on them: its own conversation back, and when the
# pane was on the other agent, a prompt that tells it where that one left off.

# shellcheck source=mux.sh
source "${BASH_SOURCE[0]%/*}/mux.sh"
# shellcheck source=agent.sh
source "${BASH_SOURCE[0]%/*}/agent.sh"

# A pane's conversations, tab-separated: the session of the agent on it, that agent, each agent's session and
# transcript, and when tt switch last moved it. $open and the archive log keep them as their last columns, so a
# line written before there were two agents (the session alone) still reads.
# shellcheck disable=SC2034 # used by the files that source this one
convs=$(formats '#{@agent_session}' '#{@agent}' '#{@agent_session_claude}' '#{@agent_session_codex}' \
    '#{@agent_transcript_claude}' '#{@agent_transcript_codex}' '#{@agent_switched}')

# Each transcript's messages as one JSON array a line, timestamp, role and text, without tool calls and their output,
# which make up most of a transcript. $since leaves out the older ones.
# shellcheck disable=SC2016 # jq's variables
claude_jq='select((.type == "user" or .type == "assistant") and .timestamp >= $since)
    | [.timestamp, .type, (.message.content | if type == "string" then . else map(.text // empty) | join("\n") end)]
    | select(.[2] != "")'
# shellcheck disable=SC2016 # jq's variables
codex_jq='select(.type == "response_item" and .payload.type == "message" and .timestamp >= $since
        and (.payload.role == "user" or .payload.role == "assistant"))
    | [.timestamp, .payload.role, (.payload.content | map(.text // empty) | join("\n"))]
    | select(.[2] != "" and (.[2] | startswith("<") | not))'

# agent_name <agent>: what the agent is called in a prompt.
agent_name() { case $1 in codex) echo Codex ;; *) echo Claude Code ;; esac }

# pickup <from> <transcript> <since> <waiting>: the prompt for an agent taking a pane over from the other one: where
# its conversation is, with a command that prints the end of it, from the time given on (the last switch, when the
# incoming agent is back in its own conversation); and what it was waiting on its person for, if it was.
pickup() {
    local from=$1 transcript=$2 since=$3 waiting=$4 name prog
    name=$(agent_name "$from")
    printf 'tt switch moved this pane from %s to you: take its work over. ' "$name"
    if [ -n "$transcript" ]; then
        if [ "$from" = codex ]; then prog=$codex_jq; else prog=$claude_jq; fi
        # On one line, in single quotes: the programs have none.
        prog=$(printf %s "$prog" | tr '\n' ' ' | tr -s ' ')
        printf 'Its conversation is in %s. Read the end of it first: this prints its messages, oldest first, ' \
            "$transcript"
        printf "without tool calls:\n\n    jq -c --arg since %q '%s' %q | tail -n 40\n\n" "$since" "$prog" "$transcript"
        [ -z "$since" ] || printf 'It took this pane over from you at %s; that lists only what came after. ' "$since"
        printf 'Then check git status and git diff, work out what was in progress, and carry on with it.'
    else
        printf 'Its conversation is not on record: check git status, git diff and git log, work out what was in '
        printf 'progress, and carry on with it.'
    fi
    [ -z "$waiting" ] || printf '\n\nWhen it stopped, %s was waiting on its person for this; ask them again:\n\n%s' \
        "$name" "$waiting"
}

# run_agent <pane> <agent> <prompt> <waiting> <conversations>: starts the agent at the pane's shell prompt on the
# pane's conversations ($convs), tagging the pane with them. When another agent was on the pane, the prompt starts
# with what the incoming one needs to take over, and the switch's time is kept for the next one.
run_agent() {
    local pane=$1 to=$2 prompt=$3 waiting=$4 cur from sc sx tc tx since session transcript now p=(-p -t "$1")
    IFS=$us read -r cur from sc sx tc tx since <<<"$5"
    from=${from:-claude}
    # Tagged before each agent had its own: the agent's session is the pane's, and Claude Code's transcript is where
    # its directory and session say.
    if [ "$from" = codex ]; then sx=${sx:-$cur}; else sc=${sc:-$cur}; fi
    [ -n "$tc" ] || [ -z "$sc" ] || tc=$(claude_dir "$(tmux display -p -t "$pane" '#{pane_current_path}')")/$sc.jsonl
    # A conversation with no transcript never got a prompt (Claude Code writes none until then): nothing to resume.
    [ -z "$tc" ] || [ -e "$tc" ] || sc='' tc=''
    [ -z "$tx" ] || [ -e "$tx" ] || sx='' tx=''
    if [ "$to" = codex ]; then session=$sx; else session=$sc; fi
    if [ "$from" != "$to" ]; then
        if [ "$from" = codex ]; then transcript=$tx; else transcript=$tc; fi
        # Back in its own conversation, the incoming agent knows what came before the last switch.
        [ -n "$session" ] || since=''
        prompt=$(pickup "$from" "$transcript" "$since" "$waiting")${prompt:+$'\n\n'$prompt}
        now=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    fi
    tmux set "${p[@]}" @agent_session_claude "$sc" \; set "${p[@]}" @agent_session_codex "$sx" \; \
        set "${p[@]}" @agent_transcript_claude "$tc" \; set "${p[@]}" @agent_transcript_codex "$tx" \; \
        set "${p[@]}" @agent_switched "${now:-$since}"
    mux_run "$pane" "$(resume_cmd "$to" "$session" "$prompt")"
}
