#!/usr/bin/env bats
# tt order: the order tt pick lists sessions in, saved by name as sessions move.

# shellcheck source=helpers.bash
source "$BATS_TEST_DIRNAME/helpers.bash"

setup() {
    setup_tt
    for s in aa bb cc; do tmux new-session -d -s "$s"; done
    order=$XDG_STATE_HOME/tt/session-order
    export TT_ORDER_GRAB=$tmp/grab
}

teardown() {
    teardown_tt
}

# plain: stdin without its colours.
plain() { sed $'s/\033\\[[0-9;]*m//g'; }

# rows: the sessions as tt order lists them, on one line.
rows() { "$tt" _order-rows | tr '\n' ' '; }

@test "with nothing saved, sessions come in tmux's order" {
    assert_equal "$(rows)" "aa bb cc keep "
}

@test "sessions the file doesn't name come after the ones it does" {
    mkdir -p "${order%/*}"
    printf '%s\n' cc gone aa >"$order"
    assert_equal "$(rows)" "cc aa bb keep "
}

@test "with nothing grabbed, j and k move the cursor" {
    run "$tt" _order-key down
    assert_output down
    assert [ ! -f "$order" ]
}

@test "l grabs the session, j and k move it and save, l lets it go" {
    run "$tt" _order-grab bb
    assert_output 'change-pointer(⇅)'
    run "$tt" _order-key down
    assert_output --regexp '^reload-sync\(.*tt _order-rows\)\+pos\(3\)$'
    assert_equal "$(rows)" "aa cc bb keep "
    "$tt" _order-key down
    "$tt" _order-key down
    assert_equal "$(rows)" "aa cc keep bb "
    "$tt" _order-key up
    assert_equal "$(rows)" "aa cc bb keep "
    run "$tt" _order-grab bb
    assert_output 'change-pointer(▶)'
    assert_equal "$("$tt" _order-key up)" up
}

@test "a session that isn't running keeps its place, and moves skip it" {
    mkdir -p "${order%/*}"
    printf '%s\n' aa gone bb cc keep >"$order"
    echo bb >"$TT_ORDER_GRAB"
    "$tt" _order-key up
    assert_equal "$(tr '\n' ' ' <"$order")" "bb gone aa cc keep "
}

@test "tt pick lists sessions, and numbers windows, in that order" {
    mkdir -p "${order%/*}"
    printf '%s\n' keep cc >"$order"
    run "$tt" _pick-rows
    # A session row's id starts with $; with no agent in it, its first word is its name.
    assert_equal "$(plain <<<"$output" | awk -F'\t' '/^\$/ { split($3, w, " "); printf "%s ", w[1] }')" \
        "keep cc aa bb "
    assert_equal "$(cut -f2 <<<"$output" | tr -d ' \n')" 1234
}
