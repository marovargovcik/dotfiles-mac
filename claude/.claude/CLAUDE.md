# Working inside herdr

When `HERDR_ENV=1`, work that will end in commits runs as a **herdr task**: its own worktree, herdr workspace and
Claude session. A session already in a task's worktree does that task in place; any other work it is asked to start,
including a follow-up, becomes a new task.

Start one with `herdr-task new -p "<hand-off>" <branch> [base]` from any checkout of the repo (`herdr-task --help`). It
prints the new pane's ID. The hand-off is the new session's first prompt and all it knows, so it carries:

- the task itself, as the user put it (e.g. `/implement OVE-17`)
- the base branch, and the PR to stack on when the base isn't the default branch
- what this session already found that the task needs

The task's work then happens in that session. This session reports the pane ID and returns to its own work; follow the
task with `herdr agent get <pane>` / `herdr agent read <pane>` when asked.

## Where a request belongs

Before acting on a request, work out where in herdr it belongs. Don't read code or edit files until you have. These
list every place that could take it:

```sh
herdr agent list | jq -r '.result.agents[] | "\(.pane_id) \(.agent_status) \(.cwd)"'  # live sessions
herdr pane list | jq -r '.result.panes[] | select(.agent_status == "unknown") | "\(.pane_id) \(.cwd)"'  # panes with no Claude
herdr-task archived                                                                   # archived worktree tasks
```

The places, most specific first:

- **A task's worktree**: a live session whose cwd is a worktree named after the ticket (`NUX-392` in
  `.../marek-nux-392-...`), or an archived task on that branch
- **A repo's workspace**: a live session whose cwd is the repo's checkout or a folder in it, or, when the workspace
  has none, a pane there with no Claude running
- **A new task** with `herdr-task new` (above), for work that will end in commits and that nothing else has
- **This session**, when it is itself the place

A direct match is the ticket key or a path from the request naming exactly one place. Then act without asking; the
request is the go-ahead. Otherwise (several places fit, only a fuzzy match like a similar label, or none) ask the user,
listing the candidates with pane IDs or branches, and recommend one.

For a live session other than this one:

1. Send it the request with `herdr agent prompt <pane> "<hand-off>"`. The hand-off carries the user's request in their
   words, plus anything this session already found that the work needs. That session keeps its own context, so don't
   repeat its background.
2. If the pane is `blocked`, don't send; tell the user it's waiting on them in that pane. If it's `working`, send anyway
   (it queues) and say so.
3. Report the pane ID and stop. Follow up with `herdr agent read <pane>` only when asked.

For a workspace pane with no Claude running, start one there on the hand-off, as `herdr-task new` does:
`herdr pane run <pane> "claude $(printf %q "<hand-off>")"`. Use a pane sitting at a shell prompt, not one running a
server or other command. Then report the pane ID and stop, as above.

For an archived task, bring it back instead of starting a duplicate: `herdr-task restore -p "<hand-off>" NUX-392`
recreates the worktree at its old path, resumes the task's Claude conversation on the hand-off and prints the pane ID.
Then report the pane ID and stop, as above.

If a ticket's worktree exists (`git worktree list` in the repo) but neither a pane nor an archive entry does, the pane
was closed: tell the user rather than starting a duplicate task.

builder-flow: I work mainly fullstack
