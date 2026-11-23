# shellcheck shell=bash
# tt switch: moves agent panes between Claude Code and Codex, for when one's usage limit runs out. The incoming
# agent resumes its own conversation in the pane, if it had one, and reads the other's for where things were left.

# shellcheck source=takeover.sh
source "${BASH_SOURCE[0]%/*}/takeover.sh"
# shellcheck source=send.sh
source "${BASH_SOURCE[0]%/*}/send.sh"

# agent_panes: every pane an agent runs in: pane, agent, state, session:window, then its conversations ($convs).
agent_panes() {
    tmux list-panes -a -F "$(formats '#{pane_id}' "#{?$live,#{@agent},}" '#{@agent_state}' \
        '#{session_name}:#{window_name}' "$convs")" 2>/dev/null | awk -F'\t' '$2 != ""'
}

# stop_agent <pane> <agent>: ctrl-c until the agent quits (the first one may only end its turn or clear its prompt)
# and the pane is back at its shell's prompt; fails if it doesn't within ten seconds.
stop_agent() {
    local i cmd
    for ((i = 0; i < 20; i++)); do
        cmd=$(tmux display -p -t "$1" '#{pane_current_command}')
        is_shell "$cmd" && return 0
        [ "$cmd" != "$2" ] || tmux send-keys -t "$1" C-c
        sleep 0.5
    done
    return 1
}

# switch_pane <pane> <agent> <from> <state> <conversations>: stops the pane's agent and starts the other on the pane's
# conversations. A blocked one's question goes along, from what its screen showed. The tags of the agent that quit
# go, as its SessionEnd hook would (which a killed one never gets to), so the incoming one's start claims the pane.
switch_pane() {
    local pane=$1 to=$2 from=$3 state=$4 conv=$5 waiting='' p=(-p -t "$1")
    [ "$state" != blocked ] || waiting=$(read_pane "$pane" 0 | tail -n 20)
    stop_agent "$pane" "$from" || {
        echo "tt: $pane: $from didn't quit; left as it was" >&2
        return 1
    }
    tmux set -u "${p[@]}" @agent \; set -u "${p[@]}" @agent_session \; set -u "${p[@]}" @agent_state \; \
        set -u "${p[@]}" @agent_seen
    run_agent "$pane" "$to" '' "$waiting" "$conv"
    echo "$pane: $from → $to"
}

# switch_cmd [--force] [claude|codex] [pane...]: moves the panes given, or every agent pane (then also what new panes
# start), to the agent; panes on it already stay. A working agent stays too unless --force, or the person asks for it
# at a terminal. With no agent given, prints what new panes start.
switch_cmd() {
    local force='' to pane agent state where conv picked=() working=() self='' answer rc=0 pids=() i
    if [ "${1:-}" = --force ]; then
        force=1
        shift
    fi
    to=${1:-}
    case $to in
    '')
        provider
        return
        ;;
    claude | codex) shift ;;
    *) die "switch to claude or codex" ;;
    esac
    for pane; do
        agent=$(tmux display -p -t "$pane" "#{?$live,#{@agent},}" 2>/dev/null) || die "no pane $pane"
        [ -n "$agent" ] || die "$pane runs no agent"
        [ "$agent" != "$to" ] || echo "$pane: on $to already"
    done
    [ $# -gt 0 ] || set_provider "$to"
    while IFS=$us read -r pane agent state where conv; do
        [ "$agent" != "$to" ] || continue
        [ $# -eq 0 ] || printf '%s\n' "$@" | grep -qxF "$pane" || continue
        # The agent running this: it goes last, from tmux, once this has returned to it.
        if [ "$pane" = "${TMUX_PANE:-}" ]; then
            self=$pane
        elif [ "$state" = working ] && [ -z "$force" ]; then
            working+=("$pane $where")
        else
            picked+=("$pane$us$agent$us$state$us$conv")
        fi
    done < <(agent_panes | fields)
    if [ ${#working[@]} -gt 0 ]; then
        printf '%s is working\n' "${working[@]}" >&2
        answer=n
        [ ! -t 0 ] || read -rp "switch those too? [y/N] " answer
        if [ "$answer" = y ]; then
            switch_cmd --force "$to" "${working[@]%% *}" || rc=1
        else
            echo "tt: left as they are; --force switches them too" >&2
            rc=1
        fi
    fi
    # In parallel: each agent takes a moment to quit.
    for i in "${picked[@]}"; do
        IFS=$us read -r pane agent state conv <<<"$i"
        switch_pane "$pane" "$to" "$agent" "$state" "$conv" &
        pids+=($!)
    done
    for i in "${pids[@]}"; do wait "$i" || rc=1; done
    [ -z "$self" ] || tmux run-shell -b "TMUX_PANE= $(printf %q "$0") switch --force $to $self >/dev/null"
    return $rc
}

# menu <pane> <client>: tt switch as a tmux menu, for a key binding: the pane, or all of them, to either agent; keys
# c and x (codex), C and X for all. What would change nothing shows greyed out (tmux greys an item whose name starts
# with -): the pane's own agent, and all to the agent every pane and new ones are on already.
menu() {
    local pane=$1 client=$2 self cur to key name n busy items=()
    self=$(printf %q "$0")
    cur=$(tmux display -p -t "$pane" "#{?$live,#{@agent},}")
    for to in claude codex; do
        name="this pane → $to" key=c
        [ "$to" = claude ] || key=x
        [ -n "$cur" ] && [ "$cur" != "$to" ] || name=-$name
        items+=("$name" "$key" "run-shell -b \"$self switch --force $to $pane >/dev/null\"")
    done
    items+=('')
    for to in claude codex; do
        read -r n busy < <(agent_panes | awk -F'\t' -v a="$to" '$2 != a { n++; if ($3 == "working") b++ }
            END { print n + 0, b + 0 }')
        name="all panes → $to" key=C
        [ "$to" = claude ] || key=X
        if [ "$n" -gt 0 ]; then
            name+=" ($n"
            [ "$busy" -eq 0 ] || name+=", $busy working"
            name+=")"
        elif [ "$(provider)" = "$to" ]; then
            name=-$name
        fi
        items+=("$name" "$key" "run-shell -b \"$self switch --force $to >/dev/null\"")
    done
    tmux display-menu -c "$client" -t "$pane" -T " agents: new ones start $(provider) " -- "${items[@]}"
}
