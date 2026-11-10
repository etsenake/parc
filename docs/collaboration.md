# Working together on Parc

Read [AGENTS.md](../AGENTS.md), [README](../README.md),
[product status](parity.md) and the [backlog](backlog.md) before editing.
Current user instructions determine the task, checkout and delegation scope.
New-machine setup follows [onboarding](developer-onboarding.md) and ends with
readiness; it does not assign feature work.

## Ownership

Work on the requested outcome, not the next row of a historical parity table.
Before editing shared files, inspect current Git state and agree exact ownership
with active contributors. Old owner names and worktree paths are not evidence
that someone is still working. Verify activity before reporting it or taking over.

When parallel work is authorized, give each helper a bounded responsibility and
disjoint files. Tell them they share the checkout and must preserve others' edits.
The task owner integrates results and remains responsible for completion. A
helper finishing an increment does not finish the overall task.

Use the existing checkout unless another workspace is explicitly authorized.
Never retarget the conversation with Cursor migration tools. Do not claim shared
engine, signing or packaging ownership without a concrete handoff from root.

For coordination across sessions, record only the current handoff in the
[backlog](backlog.md): task, owner, affected paths/interfaces, blocker and next
action. Replace it when the state changes and remove it after delivery. Keep
short-lived coordination and check receipts in ignored `build/` or `work/`.
Do not create another ledger, dated progress log or permanent agent roster.

## Delivery

Complete user-visible behavior, integration and applicable checks within scope.
Backend dependencies need a concrete interface and receiving owner; a disconnected
control is not a delivered feature. Publish a completed independent component
without waiting for a separately owned consumer, and record the integration
handoff. Necessary unowned work remains the task owner's responsibility.

Fix actionable problems within scope. Outside-scope work needs a concrete next
action in the backlog and disclosure to the user in the same turn. Preserve explicit
deferrals and existing features; do not silently turn either into completed work.

For implementation work with authorized delegation, use a fresh read-only
reviewer on the exact changed source, including new files. Author and reviewer
exchange findings directly, fix them and re-review material changes. Review
correctness, lifetimes, races, data safety, regressions and necessary coverage.
Do not rerun already-passed checks or repeat reviews of unchanged cleared source.
Root-only work is reviewed directly by root. Finished agents retire rather than
being reassigned; unfinished original assignments may resume.

## Checks and publication

Read a check's implementation before running it. Never launch apps/browsers,
including headless or test copies, or take app screenshots without explicit
authorization for the current task. For a live timing investigation, use the
[runtime tracing workflow](runtime-tracing.md), including permission, Codex
computer-use routing and prompt release of control. Otherwise use permitted
compiler, model and inert component checks. Documentation-only changes need
size, link and diff checks, not an engine or app build. See
[development setup](development-setup.md)
for Swift typecheck and whole-module SIL commands.

Keep each check's command, result and source identity in ignored output. Be
truthful about the checks run. Do not invent validation-only backlog work or
repeat release-timing caveats; report a blocked check when its specific cause
materially affects the task. An old receipt does not cover later source changes.

Completed implementation and applicable permitted checks close a fix. Do not
wait for the user to confirm it or grant browser access; reopen only on a new
report or concrete defect evidence. Separate a failing test setup from a failing
product before making behavior changes. Do not chase harness uncertainty with
repeated browser runs or speculative patches.

Update the affected guide, product status or backlog in place. Follow the
[documentation policy](documentation.md): one home per fact, normal 150–300 lines,
hard 500-line maximum, no append-only delivery narratives. Changelogs are exempt
and retain their full history and generation.

Fetch current main, reconcile peers' edits safely, inspect the exact final diff,
and run applicable checks plus `python3 scripts/check-docs.py` and
`git diff --check`. Commit using the single-line format in AGENTS and immediately
push. Verify remote SHA/ancestry. If main advances, fetch and reconcile without
force-pushing or dropping changes. Do not accumulate unpublished commits.

## Shared engine and retained work

Only the explicitly assigned owner operates shared engine apply/build/seal/package.
Keep active inputs fixed through sealing and packaging. Preserve source changes,
compiled objects and caches; publish unrelated safe work without retargeting a
live build. Fetch main before overlay numbering or operations and use current
manifest hashes. Builds and overlay application require explicit authorization.

Read real process state and receipts before acting on a lock or old timestamp.
Never restart, terminate or delete work merely because a session disconnected.
Use ignored checkout-local `work/` for engine source and `build/` for outputs.

Cleanup requires confirming a path's owner, active use, uncommitted work and
publication status. Do not delete another contributor's candidate based only on
age or a Git match. Preserve profiles, signed releases, unique diagnostics and
compiler caches. See [engine artifacts](engine-artifacts.md) and
[release guide](master-release.md) for their concrete contracts.
