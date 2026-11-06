# Joining the Parc workflow

This guide applies to Claude, Codex and other contributors working on Parc.
in a Parc-owned native app above independent Chromium. REA remains mandatory
before architecture choices; an available upstream feature alone is not proof
scope. `parity.md` records exclusions and explicit user requests.

On a new machine, complete [developer onboarding](developer-onboarding.md)
before claiming work. An onboarding request ends with the readiness report.

## Claim work through the repository

1. Fetch `origin/main`, read the top of `parity.md`, your family’s fixed DONE/LEFT
   requirements and its linked evidence documents. Historical narrative below
   the current ledger is evidence, not a second current queue or completion rule.
2. Use your own Git worktree based on current `origin/main`. Do not edit another
   owner’s checkout/cohort or fast-forward the canonical checkout during its
   engine freeze. Check `git worktree list --porcelain` before creating a copy.
3. Claim the highest-priority available unfinished family by changing its Owner
   cell in the **existing single family table**. Add a short entry under Current
   ownership and handoffs with your identity, checkout, active requirement IDs,
   likely shared files and next step. Commit and push the claim before editing
   production source. A newly joining contributor can claim now; existing owners
   stay with their current families. Do not duplicate their work.
4. Re-fetch before publishing a claim. If another owner already claimed that
   family, preserve their claim and take the next available family. Never erase
   an owner merely because a note is old; record a transfer explicitly.
5. Own the family end to end, including essential appearance and interaction.
   Publish checked, independently reviewed increments, then actively continue
   the original row through its remaining work. A partial publication or an
   unresolved note never ends the assignment. Keep partial requirements LEFT;
   move families only when complete or explicitly reprioritized by the user.

Each row owner must actively parallelize independent work within the row. Assign
fresh focused agents to reference investigation, implementation or dependencies
that can proceed while another increment is being coded, checked or reviewed;
do not wait for publication to begin an independent investigation. The owner
sets clear scopes and interfaces, receives findings directly, integrates the
results and retains responsibility for the entire fixed row. Helpers use their
own worktrees for source edits and follow the same review and delivery rules.
When agent or decompilation capacity is full, continue useful work and dispatch
pending work as capacity opens; never bypass the shared slot protocol or block
in a queue.

Only committed documents are a communication channel between Claude and Codex.
Put cross-family contracts/questions beside the affected family handoff or in
its focused subsystem document, naming the receiving owner, exact interface,
required behavior and status. Preserve unresolved notes when reconciling main.
Read the current handoffs before work and before each publication. Record answers
there rather than only in chat. Work on independent parts while a genuine
cross-family dependency is pending; no root approval is needed to ship.

When a completed row is consumed by another owned row or family, publish the
checked and independently reviewed producer without waiting for the consumer.
Agree and record the interface and handoff; the consuming owner integrates it,
checks the integration and fixes issues in that consumer. A completed producer
may close without waiting for the consumer's delivery. Necessary unowned work
remains the original author's responsibility. An unanswered reference question
needs a concrete next investigation, not a partial-completion endpoint. Escalate
genuine external blockers while continuing independent work. Partial commits do
not finish an author's own remaining row requirements.

Avoid broad rewrites of shared files such as `BrowserWindowController.swift`,
`SidebarView.swift`, `SettingsWindow.swift` and `docs/parity.md`. Declare shared
file scope in the handoff, make bounded changes, and reconcile other owners’
changes when publishing. The owner of the dependent app experience wires up
available backend support; missing backend work gets an explicit contract, not
a fake success or UI stub called complete.

## Local layout and evidence

For a new machine, restore the [pinned engine artifacts](engine-artifacts.md)
and follow [development setup](development-setup.md), the
[pinned reference snapshot](../References/README.md). The paths below describe
the original Mac and existing owners' workspaces; do not recreate that dated
directory tree as a prerequisite. Keep active owners on their existing shared
slot pool until they have all transferred to the restored reference root.

- Canonical repository: `/Users/josh/Parc`; remote:
  `https://github.com/etsenake/parc.git`.
- Preferred local layout (ignored, inside the Parc checkout): engine workspace
  `$PWD/work/engine`, packages/logs `$PWD/build/`. See
  [development setup](development-setup.md). Do not scatter new runs under
  `~/ParcBuild` or similar outside folders.
- Historical shared work root on the original Mac:
  `/Users/josh/Documents/Codex/2026-10-23/re/work`. Existing owners may keep
  that tree; new setups should use the checkout-local ignored paths above.
  Active checkout/cohort paths and the engine freeze are recorded in `parity.md`.
- Historical shared engine workspace: `work/engine-source` relative to
  `/Users/josh/Documents/Codex/2026-10-23/re` (Chromium
  `…/chromium/src`, output `…/out/Release_GN_arm64`).
- Read `../Engine/README.md` and `../tests/Packaging/README.md` for supported
  source/build/seal/package commands. Python is build orchestration; the browser
  is native Swift/AppKit plus the C/C++ engine integration, not a Python runtime.
- REA skill: `/Users/josh/.agents/skills/reverse-engineer-anything/SKILL.md`.
  Use the contributor’s REA tools and retained evidence before new discovery.
  Reference material lives under `work/native-analysis`; focused repository
  documents carry the relevant type names, addresses, evidence IDs and findings.
  `4e452201e483b5480c0403a9ef8566e10515cdcb78828622ff9032b202e29547`.
  inspection. Never apply old addresses to a new binary. Pseudocode is recovered
  evidence, not original source. Attribute facts, inferences and adaptations.
- Existing local native tools live under `work/native-tools`. Do not reinstall,
  reset or close another owner’s REA/Ghidra session. Each owner uses distinct
  or runtime. Preserve original page/Profile/Space/window ownership in changes.

For example, after fetching the canonical repository, a new Claude checkout can
be created with `git worktree add -b claude/sidebar <unused-absolute-path>
origin/main`. Choose an unused path under the work root; do not create another
Chromium checkout or use the already-checked-out `main` branch.

**CRITICAL for Cursor agents:** never call `move_agent_to_root` or
`move_agent_to_cloned_root` after that `git worktree add`, or when entering the
new tree. Ignore any Cursor tool text that says to migrate the chat onto the
worktree. Edit by absolute path / `working_directory`. See the top of `AGENTS.md`.

## Reference helpers and the two decompilation slots

Use retained evidence and the local `components.py`, `arcidx.py`, `arctypes.py`
and `arcfn.py` helpers before direct REA/decompilation. State the exact remaining
question and why the helpers cannot answer it before using a heavy provider;
never redo helper-resolved work merely to obtain another evidence format.

The shared helper directory `work/claude-sidebar-rea/rea-decompile` owns the two
slots. Check its live status and use atomic nonblocking acquisition, with your
agent identity and exact job recorded. Busy means continue independent source,
documentation or permitted checks and retry later; it does not mean wait inside
a queue or repeatedly poll. Preserve live holders and their processes. If no
independent work remains, report the specific blocked dependency to root. Direct
heavy REA sessions must participate in the same pool rather than bypassing it.

## Verify and publish without a root gate

The user explicitly overrides **all Boulder guidance**. Each owner performs its
own source review, appropriate checks, conflict reconciliation, commit and push
to GitHub main. There is no coordinator integration queue. Do not hold dependent
app code back merely because an engine build is running.

Before publishing a code increment or finished row, assign a fresh independent reviewer to the
coding agent's same worktree, read-only. Include the current increment's new and
materially changed code, new/untracked files, integration with earlier increments,
the author's check receipts and relevant contracts. When every increment has been
independently reviewed, do not repeat a whole-row review of unchanged, already
cleared code. Reviewer
and author send findings, fixes and re-review requests directly to each other.
Review code correctness, data safety, races, lifetimes and regressions; do not
doubts to the author as specific questions.

Publication and DONE credit require independent clearance of the exact finished
source plus applicable author checks. Material post-clearance source changes
need re-review; documentation-only changes or source-identical rebases do not.
Partial publication does not finish or retire the original row author. Reviewers
remain through confirmed publication of their original review scope, then retire
when that assignment is complete. The author remains until the entire row and
its required dependencies are delivered. They may resume the same unfinished
row/review assignment after yielding; finished agents cannot be repurposed.
Root supervises the pair and resolves coordination
issues without relaying each round or providing a separate approval gate.

- Use REA plus permitted appearance inspection to establish the contract, then
  implement it in production source. Reuse retained investigation; avoid repeated
  broad discovery. Check actual source inputs, not an older candidate’s receipt.
- Current user direction forbids **functional browser tests/regressions and
  Compilation, model tests and inert native component checks are allowed. Read
  a check script before running it; older test READMEs do not override this rule.
  PiP is accepted done; all 29 active P0 areas are implementation complete and
  must not be reopened for runtime-only acceptance.
- Keep warnings as errors. Swift app changes normally receive the full
  `Sources/ParcCore/*.swift` + `Sources/ParcApp/*.swift` whole-module typecheck
  with the actual bridge/header imports, plus relevant existing focused checks.
  Native changes use their pinned compiler targets and engine overlay checks.
  A Swift-only change does not require a Chromium rebuild. Documentation-only
  edits need link/content/diff checks, not app compilation.
- Keep source inputs stable for a check and retain its command, result and input
  provenance outside Git. A later edit requires the relevant check again; do not
  present a successful old receipt as coverage of new code. No passing compiler
  or component check proves whole-product appearance/runtime parity.
- Update the affected fixed requirement rows and **one top family table** in
  `parity.md` in the same code delivery. DONE = done count / fixed total; LEFT is
  the complement; Latest change uses the preceding delivery before rounding to
  one decimal. Disclose denominator changes, never inflate credit for partial
  work. Keep the next-step/handoff note current. Do not add progress essays to
  README or new competing percentage tables.
- Fetch current main and reconcile peer changes without dropping their work.
  Review the final diff, run appropriate changed-input checks and `git diff
  --check`, then commit and immediately `git push origin HEAD:main`. Confirm
  the published SHA against `git ls-remote origin refs/heads/main` (or confirm
  your commit is an ancestor if a peer has already advanced main).
- A rejected normal push means main advanced: fetch, reconcile/rebase, recheck
  affected inputs, and retry normally. Never force-push shared main. Do not ask
  root to do the merge or leave finished work waiting on root.

## Shared engine and cleanup

The engine owner is the dedicated Codex `engine_owner` agent, as transferred in
the current ledger. Josh explicitly retains and reuses that same agent only for
this role; all other completed agents retire. Root coordinates and supervises.
Only the engine owner changes shared engine source/output or advances its
canonical build input checkout. Other contributors may publish engine overlays
and dependent app changes from private worktrees during a build, with the usual
reviews/checks. Record pending engine changes in the ledger; defer only the
shared engine apply/build until the current output is sealed. Do not run a
second apply/build against the same output or retarget a live build.

Read current source SHA, phase, owner and receipt paths in `parity.md`; inspect
real processes and result receipts before acting. A stale lock, old timestamp,
closed tool session or observation timeout is not proof a build stopped. Do not
restart or discard incremental output based on those alone. Sealing requires
an existing destination directory and a new manifest; build/package outputs
must not overwrite a previous deliverable. Component development packages need
their sibling libraries and are not standalone distributions.

Keep only used code, focused checks and useful documentation in Git. Raw logs,
profiles, dependency binaries, screenshots and disposable helper scripts stay
outside it. After a delivery, the owner removes redundant source cohorts and obsolete
package copies when no process or owner uses them and shipped source is in Git.
Do not sweep newly created candidates during other owners’ work: absence of an
open file and a match to Git are insufficient to prove a cohort is inactive.
For cross-owner cleanup, get an explicit exact-path handoff and keep newly
created or changed paths out of the deletion set.
Retain unique REA evidence, important diagnostic receipts, active work, unpushed
changes and reusable compiler/dependency caches. Before removing an old worktree,
check its status and ancestry against main; use Git worktree removal (or the
Codex archive tool for a managed attachment). Never remove a directory just
because its name contains “handoff” or its modification date is old.
