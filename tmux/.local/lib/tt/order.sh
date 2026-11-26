# shellcheck shell=bash
# tt order: the order sessions are listed in, which tmux doesn't keep. It lives in a file, a session name per line,
# so it outlasts the server; sessions not in it come after, in tmux's order.

# shellcheck source=pick.sh
source "${BASH_SOURCE[0]%/*}/pick.sh"

# order_all: every name in the order file, then the sessions it doesn't name yet.
order_all() {
    {
        [ ! -f "$order" ] || cat "$order"
        tmux list-sessions -F '#{session_name}' 2>/dev/null
    } | awk '!seen[$0]++'
}

# session_order: the running sessions, in order.
session_order() {
    awk 'NR == FNR { live[$0]; next } $0 in live' <(tmux list-sessions -F '#{session_name}' 2>/dev/null) <(order_all)
}

# order_move <session> <up|down>: swaps the session with the running one above or below it and saves the order. Names
# of sessions that aren't running keep their place, so a session back after a restart lands where it was.
order_move() {
    local name=$1 step=1 all i j s
    local -A live
    [ "$2" = up ] && step=-1
    while IFS= read -r s; do live[$s]=1; done < <(tmux list-sessions -F '#{session_name}')
    mapfile -t all < <(order_all)
    for ((i = 0; i < ${#all[@]}; i++)); do [ "${all[i]}" = "$name" ] && break; done
    for ((j = i + step; j >= 0 && j < ${#all[@]}; j += step)); do
        [ -n "${live[${all[j]}]:-}" ] || continue
        all[i]=${all[j]} all[j]=$name
        mkdir -p "${order%/*}"
        printf '%s\n' "${all[@]}" >"$order.$$" && mv "$order.$$" "$order"
        notify
        return 0
    done
}

# order_key <up|down>: j or k in tt order, as fzf actions: moves the cursor, or the grabbed session (named in a file,
# not read from fzf's cursor, which lags when keys are held down).
order_key() {
    local name i
    if [ -s "$TT_ORDER_GRAB" ]; then
        name=$(cat "$TT_ORDER_GRAB")
        order_move "$name" "$1"
        i=$(session_order | awk -v name="$name" '$0 == name { print NR; exit }')
        echo "reload-sync($(printf %q "$0") _order-rows)+pos(${i:-1})"
    else
        echo "$1"
    fi
}

# order_grab <session>: l in tt order: grabs the session, or lets go of the one grabbed; the pointer says which.
order_grab() {
    if [ -s "$TT_ORDER_GRAB" ]; then
        rm -f "$TT_ORDER_GRAB"
        echo 'change-pointer(▶)'
    else
        printf '%s\n' "$1" >"$TT_ORDER_GRAB"
        echo 'change-pointer(⇅)'
    fi
}

# order_cmd: the sessions in order: j and k move the cursor, l grabs the session under it (and lets it go), and j and k
# then move the session. Each move is saved at once; esc closes.
order_cmd() {
    local self
    self=$(printf %q "$0")
    mkdir -p "$pickers"
    export TT_ORDER_GRAB=$pickers/order-grab.$$
    trap 'rm -f "$TT_ORDER_GRAB"' EXIT
    session_order | fzf --no-input --no-sort --pointer='▶' \
        --header='j/k: move  l: grab/let go  esc: close' \
        --bind="j:transform($self _order-key down)" \
        --bind="k:transform($self _order-key up)" \
        --bind="l:transform($self _order-grab {1})" \
        --bind=enter:abort >/dev/null || true
}
