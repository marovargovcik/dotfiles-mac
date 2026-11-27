# tt pick's rows, from a line per pane of tmux list-panes, the fields of pick_rows' format:
#   1 session id, 2 session name, 3 its window count, 4 window id, 5 window index, 6 window name, 7 its pane count,
#   8 window role, 9 pane id, 10 pane index, 11 whether it's the window's active pane, 12 what it does, 13 title,
#   14 directory name, 15 agent state, 16 whether the agent was seen since
# A row starts with its tmux id and a tab, then the window's code (blank on session and pane rows) and a tab; fzf
# shows what follows the id, and searches the rest apart from the code. Columns are as wide as their widest value,
# so the title gets what's left of the list's width. Run with LC_ALL=C: width() counts characters from UTF-8 bytes.
#
# With -v filter=1, the rows for a query instead: the window whose code is -v code first, then a rule, then the rows
# whose ids are in -v matched, each with its session's row (and a pane with its window's) above it for context.

# How urgent an agent's state is: blocked, done and not looked at, working, done and seen, nothing.
function rank(state, seen) {
    return state == "blocked" ? 4 : state == "done" && seen == "" ? 3 : state == "working" ? 2 : state == "done" ? 1 : 0
}

function icon(r) {
    return r == 4 ? "\033[31m⚠\033[0m" : r == 3 ? "\033[32m✓\033[0m" : r == 2 ? "\033[33m…\033[0m" : r == 1 ? "\033[2m✓\033[0m" : " "
}

# code_of: the nth window's code: 1-9, then a for 10, a1-a9, b for 20, and so on.
function code_of(k) {
    return k < 10 ? k "" : sprintf("%c", 96 + int(k / 10)) (k % 10 ? k % 10 : "")
}

function repeat(s, n,  t) {
    t = ""
    while (n-- > 0) t = t s
    return t
}

# width: s's characters, not counting UTF-8's continuation bytes.
function width(s) {
    gsub(/[\200-\277]/, "", s)
    return length(s)
}

function pad(s, w) { return s repeat(" ", w - width(s)) }

function widen(name, s) { if (width(s) > widths[name]) widths[name] = width(s) }

# Every row waits for the end, to learn the columns' widths and the most urgent state under each window and session.
{
    r = rank($15, $16)
    sub(/^[^[:alnum:]]+ /, "", $13)  # Claude Code's spinner before the title
    info = $13 != "" ? $13 : $14
    widen("doing", $12)

    # A session: its name in bold, a rule, and its window count.
    if ($1 != session) {
        session = $1; nwindows = 0
        kind[++n] = "s"; id[n] = $1; session_of[n] = $1; s = n
        head[n] = sprintf("\033[1m%s\033[0m \033[2m%s %d window%s\033[0m", $2, repeat("─", 40 - width($2)), $3, ($3 == 1 ? "" : "s"))
    }

    # A window hangs under its session: its code, counting across sessions, then index, name, role, and its active
    # pane's doing and info.
    if ($4 != window) {
        window = $4; npane = 0; last_window = (++nwindows == $3)
        kind[++n] = "w"; id[n] = $4; window_of[n] = $4; session_of[n] = $1; w = n; wcode[n] = code_of(++nwin)
        session_row[n] = s; session_name[n] = $2
        tree[n] = last_window ? "└─" : "├─"; index_[n] = $5; name[n] = $6; role[n] = $8
        widen("index", $5); widen("name", $6); widen("role", $8)
    }
    if (r > window_rank[$4]) window_rank[$4] = r
    if (r > session_rank[$1]) session_rank[$1] = r
    # session:window dimmed at the end, so typing a session name also finds what's under it.
    if ($11 == 1) { doing[w] = $12; text[w] = info; tag[w] = $2 ":" $5 }

    # A pane gets a row of its own only in a window split into several.
    if ($7 > 1) {
        kind[++n] = "p"; id[n] = $9; rank_[n] = r; session_row[n] = s; window_row[n] = w
        tree[n] = (last_window ? "   " : "│  ") (++npane == $7 ? "└─" : "├─"); index_[n] = "." $10
        doing[n] = $12; text[n] = info; tag[n] = $2 ":" $5 "." $10
        widen("pane", index_[n])
    }
}

# row: the ith row, with extra after it.
function row(i, extra,  h, ic) {
    if (kind[i] == "s") return sprintf("%s\t%-*s\t%s %s%s", id[i], nw, "", icon(session_rank[session_of[i]]), head[i], extra)
    if (kind[i] == "w") {
        h = tree[i] " " pad(index_[i], widths["index"]) " " pad(name[i], widths["name"])
        if (widths["role"]) h = h " " role[i]
        ic = icon(window_rank[window_of[i]])
    } else {
        h = tree[i] " " index_[i]
        ic = icon(rank_[i])
    }
    return sprintf("%s\t%-*s\t%s %s  %s  %s  \033[2m%s\033[0m%s", id[i], nw, wcode[i], ic, pad(h, wh), pad(doing[i], widths["doing"]),
        text[i], tag[i], extra)
}

END {
    nw = nwin >= 10 ? 2 : 1
    # A window's head: tree, index, name and role (when any window has one). A pane's label pads to the same width,
    # so doing lines up under it.
    wh = 2 + 1 + widths["index"] + 1 + widths["name"] + (widths["role"] ? 1 + widths["role"] : 0)
    if (5 + 1 + widths["pane"] > wh) wh = 5 + 1 + widths["pane"]
    if (!filter) {
        for (i = 1; i <= n; i++) print row(i, "")
        exit
    }
    split(matched, m, " ")
    for (j in m) is_match[m[j]]
    for (i = 1; i <= n; i++) if (id[i] in is_match) {
        keep[i] = kept = 1
        if (kind[i] != "s") keep[session_row[i]] = 1
        if (kind[i] == "p") keep[window_row[i]] = 1
    }
    # The window with the code, marked with it (so fzf highlights it) and its session's name, then a rule that goes
    # nowhere.
    for (i = 1; i <= n; i++) if (code != "" && wcode[i] == code) {
        print row(i, "  \033[1m◀ " code "\033[0m · " session_name[i])
        if (kept) printf "-\t%-*s\t\033[2m%s\033[0m\n", nw, "", repeat("─", 40)
    }
    for (i = 1; i <= n; i++) if (keep[i]) print row(i, "")
}
