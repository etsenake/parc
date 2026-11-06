# Visual review workflow

October 31 to November 1 sessions so any AI session can run it the same way.
Josh reviews visuals when he is present. When he is away, the coordinating
session stands in for him and judges by the same standard.

## The standard

beats a reasonable-looking guess, and an honest recorded gap beats an invented
answer. Josh notices and rejects:

  "Your new tabs appear here" text. Remove it.
  colours that ignore the Space theme.
- Wrong strength or texture, such as grain about four times too heavy, or the
  focused and unfocused window states drawn the same.
- Interaction feel: a dragged picker dot not staying under the pointer, the
  wrong cursor, hover plates that don't match, missing or wrong animations.
- Layering and separation, such as a floating sidebar that doesn't lift off the
  page, or a button that sits under page content.

## When Josh sends screenshots

   context and the images themselves. If the labels contradict what you see,
   say so in one sentence and go by what the images show.
2. **Describe each difference in plain words** (what is wrong, where, and in
   which app) and confirm the list back in one short message.
3. **Split the work into clearly bounded jobs.** Each job gets its own
   worktree and a fresh agent, plus:
   - the screenshots themselves as attachments, with absolute paths;
   - the shared brief's rules;
4. **Investigate yourself in parallel.** Read the code that draws the thing.
   Several of the best fixes came from the coordinator: the grain multiplier,
   the picker drawing its dots upside down, the tooltip colour "mismatch" that
   was really the harness misreading a JPEG. Pass a finding to the right agent
   straight away, interrupting it if needed.

## What every agent does before checks or review

- Build a throwaway offscreen harness under the worktree's ignored `build/`.
  It draws the real changed views into bitmaps at 2x, in a light theme like
  ships under `Sources/`. Harnesses never activate the app, become frontmost
  or take key focus.
  than `colorAt`, which misreads untagged images. Offscreen windows are never
  key, so render the focused and unfocused states explicitly.
- Report the renders first, before tests, docs or review. Visuals usually
  change once someone looks at them.

## How the coordinator judges a render

against the agent's description of it. Check the agent's numbers: measured
differences of a few colour levels or under a point are matches, and anything
visible at normal size is not. Question claims that don't fit what you see.
can't show something (behind-window blur, the real popover material), say so
rather than calling it matched.

**When Josh is present:** show him each render inline, one image at a time.
doesn't match, then wait for his verdict. Never re-show an image he has
already reviewed.

**When Josh is away:** approve or reject it yourself by the standard above,
with the same care. Approve when it matches the reference and the recovered
values. Send it back with specific, measured differences when it doesn't.
Record anything you had to infer.

**If Josh doesn't respond to a screenshot, assume he is away and keep the
work moving.** Judge it yourself, continue, and report what you decided. A
missing reply is never a reason to stop.

## After visual approval

The agent writes its tests, docs and checks. A fresh independent reviewer then
reads the change, findings go back to the same author, and fixes are
re-reviewed. Before pushing, rebase onto current main, then rerun the checks
that compile any file the rebase brought in, the typecheck and SIL. Push one
change at a time, with a one-line commit message. Gaps an agent or reviewer
finds while working on something Josh asked for are part of that work. Fix them
or record them in the ledger; never drop them.

## Keeping work moving

- Never block on a question. See the rule in `AGENTS.md` and
  `.cursor/rules/never-use-question-tool.mdc`.
- Read every agent result as it arrives. Two finished results once sat
  unnoticed for over half an hour.
- Never wait idle on agents. Do your own share of the work in parallel.
- Size the number of running agents to the machine's actual CPU and memory.
  Reviewers are light; builds and harnesses are heavy.
- Engine builds never take priority over finishing and shipping the app work
  already on deck.

## Where this has held up, and where it hasn't

It held up when Josh supplied references. His verdict on work the coordinator
approved while he was away was "lovely, no notes", and in one round he found
only one missed issue (the Spaces add button sitting under the page). It failed
on three things:

- Showing Josh an image he had already reviewed.
- One night of bad prioritisation. The coordinator paused app work for an
  engine build, then sat blocked on a question for about five hours while
  Josh slept. Finished agent work went unreviewed and nothing shipped.

Those failures are why the rules above exist.
