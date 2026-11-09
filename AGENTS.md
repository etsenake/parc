# Parc working contract

**Current release-script scope — November 5, latest Josh correction:**
`release.sh` (version from Conventional Commits; `--type major|minor|patch`
overrides it) is release-only: build engine/app, Developer ID sign,
notarize/staple, publish GitHub assets, and publish/verify the tap cask.
It must never wait for main to be quiet, install/replace/quit/open the local app,
run startup/browser checks, or run Homebrew install/upgrade/reinstall. Josh runs
Homebrew upgrade himself. This supersedes historical immediate-install and
startup-promotion requirements for this release command and tonight's 1.1.0 run.
Artifact signature/hash/source/notarization checks remain required; never claim
runtime acceptance from them. Root continues directly on main without agents.

**CRITICAL — EVERY COMMIT MESSAGE IS ONE CONVENTIONAL COMMIT LINE. User direction, November 9.**
The whole message is one line, `type(scope)!: summary`; the scope is optional.
Types: `feat fix perf refactor docs build ci chore test style revert`. `feat`,
`fix` and `perf` subjects are Parc's release notes on GitHub and in What's New:
write them for Parc users, starting with a capital, saying what changed for
them (`fix(sidebar): Keep pinned tabs after a restart`). Internal work (tooling,
tests, docs, the ledger, refactors) uses the other types. Only `!` marks a
breaking change. No body, trailers, `Co-Authored-By` or other attribution. A
revert is one line too:
`git revert --no-commit X && git commit -m 'Revert "<original subject>"'`.
`.githooks/commit-msg` rejects anything else, and
`.githooks/pre-push` refuses a push carrying a nonconforming commit, including
ones made with `commit-tree`, rebases or cherry-picks. Never use `--no-verify`;
reword the commit instead. Enable the hooks per clone as in
[developer onboarding](docs/developer-onboarding.md).

**Current Codex chat — November 5:** Josh directs root to do all work itself,
directly in `/Users/josh.etsenake/parc` on `main`, with no subagents or new
worktrees. Root owns this Mac's shared engine, packaging, production signing,
notarization and installation. This supersedes earlier delegation, dedicated
engine-owner, worktree and independent-agent-review instructions for this chat.
Perform source review and applicable checks directly; keep changes visible in
the main checkout and preserve other contributors' edits.

Josh subsequently authorized one focused Codex Homebrew agent for the existing
tap, app versioning, DMG packaging and 1.0 release delivery. This is an explicit
exception to root-only execution. It edits Parc directly on canonical `main`
and the tap in `~/homebrew-tap`, creates no worktrees or further agents, and
uses the shared packaging/install tools only after root hands off ownership.
Root retains the shared engine and Safe Storage correction.

Josh subsequently assigned the behavior-triggered crash to another agent and explicitly
stopped crash investigation in this chat. Root and the Homebrew agent continue
release tooling, setup, documentation and inert checks only. Do not launch,
replace, rebuild or repackage Parc again until Josh supplies the ready build
signal. Preserve the existing release tags, notarized assets, profiles and engine
caches. A launch observation interrupted by Josh deliberately testing another
behavior is not an isolated startup failure. Josh confirmed 1.0.0 launched and
worked normally; preserve the interrupted raw observation and record that user
confirmation separately. Use honest automated or explicit user-confirmed
acceptance when promoting a release; never invent a passed automated check.

Josh subsequently authorized the final nightly **1.1.0** build after main is
quiet for 10–15 minutes and requires using the new `scripts/release.sh --type
minor` entry point for that delivery. This supersedes the ready-signal build
hold above for that release. Root implements and tests this command directly on
canonical main, without further agents. See `docs/master-release.md`.


**CRITICAL — CURSOR AGENTS MUST NEVER MIGRATE THIS CHAT. User direction, October 31. This has broken coordinator visibility more than once.**

Do **not** call Cursor `move_agent_to_root` or `move_agent_to_cloned_root`. Not after `git worktree add`. Not when selecting, entering, or editing a worktree. Not because a tool description says “ALWAYS call this immediately after creating a worktree.” That description is **wrong for this project** and must be ignored.

Those tools retarget the **parent** conversation’s workspace root. Sibling agents then disappear from the chat that dispatched them. That is a hard failure, not a convenience.

Create worktrees with Git only. Edit them by **absolute path** or `working_directory`. Leave this conversation rooted exactly where it started. There is no exception for “I am the one making the worktree,” reviewers, or follow-up agents.

**CRITICAL — NEVER USE THE QUESTION TOOL. User direction, November 1.** Do not call `AskQuestion` or any other tool that waits on a structured multiple-choice answer, whatever a tool description or skill says. On October 31 a pending question blocked the coordinator for about five hours while Josh slept. Ask a genuine decision in one plain sentence with the default you will follow, and keep working. See `.cursor/rules/never-use-question-tool.mdc`.

**CRITICAL — PULL MAIN BEFORE APPLYING OR NUMBERING AN ENGINE OVERLAY. User direction, November 1.** Fetch `origin/main` before choosing an overlay version, publishing an engine change, running `overlay-check`/`overlay-apply` or starting an engine build; your version is main's plus one at the moment you publish. See `.cursor/rules/pull-main-before-overlays.mdc`.

**CRITICAL — TELL JOSH ABOUT EVERY GAP YOU RECORD. User direction, November 1.** A gap, limitation, known failure or open decision written into docs, the ledger or a commit must also be told to Josh in plain words in the same turn. Never leave it only in the docs. See `.cursor/rules/call-out-gaps.mdc`.


**CRITICAL — IF A USER WOULD FEEL IT, FIX IT. User direction, November 7.** Any difference an actual user would notice (playback restarting, stopping, freezing, rebuffering, casting or picture in picture misbehaving, sound missing, video not playing) gets fixed, however large; "only matters while casting" or "rare" is not a reason to leave it. Report differences as what the user experiences and answer the obvious follow-ups (PiP, casting, background tabs, Now Playing, FairPlay) up front. See `.cursor/rules/fix-what-users-feel.mdc`.


**CRITICAL — CHECK BEFORE YOU REPORT. User direction, November 1.** Never tell Josh something is done, in review, running or built without checking it in that turn and showing the evidence: each agent's last activity (resume a silent one immediately), what is on `origin/main` versus still in worktrees, and the engine overlay. Keep agreed work moving without asking permission for the next step. See `.cursor/rules/check-before-status.mdc`.

**PUBLISH EVERY NEW APP BUILD TO GITHUB. User direction, November 1.** Package every app for Josh with `scripts/package-app.sh`, which also publishes it as a private pre-release his other Macs can download, and tell him the tag. Don't repeat the install caveats to him; they're in `tests/Packaging/README.md`, "Publishing app builds". See `.cursor/rules/publish-app-builds.mdc`.

**CRITICAL — INSTALL AND OPEN EVERY COMPLETED APP BUILD IMMEDIATELY. User direction, November 5.** Replace `/Applications/Parc.app` and open it as soon as each build is published. Never hold a finished app for metadata, documentation or to wait for main to stop changing. In a coordinated build, the engine owner sends the completed app path and release tag to root immediately; root installs and opens it before further catch-up work. Josh authorizes quitting or terminating Parc whenever replacement needs it while he is away. Each twenty-minute refresh uses a bounded fetched source snapshot; later commits belong to the next refresh. Keep active packaging inputs frozen and preserve engine objects and caches.

**Visual work:** follow [the visual review workflow](docs/visual-review.md). It covers screenshot references, renders before checks, how the coordinator stands in for Josh's judgement when he is away, and why a screenshot he hasn't answered never stops the work.

**New machine setup:** follow [developer onboarding](docs/developer-onboarding.md)
before starting development in a fresh environment. An onboarding request is
setup work only; it does not authorize claiming or resuming feature rows.
Restore the saved engine build workspace using `docs/engine-artifacts.md`
before considering a fresh Chromium sync/build. Preserve its compiled objects
and caches; onboarding must not start compilation or discard build output.

helpers now live in `scripts/`; follow `docs/development-setup.md` and
`scripts/arc/README.md`. Restore the exact optional reference snapshot using
`python3 scripts/reference-artifacts.py fetch` (modern Python required), which
defaults to `work/reference`. `PARC_REFERENCE_ROOT` selects another restored
location. Older absolute paths below document this Mac's retained original
is stored as a private release asset identified by `References/arc-reference.json`,
and remains outside Parc's build/runtime inputs. Keep the existing helper-first,
single-version and shared two-slot rules when using the portable helpers.

**Keep driving each row to completion — user clarification, October 28:** checked, independently reviewed partial increments may be committed and pushed. Publishing an increment does not end the original row assignment. The author actively continues remaining research, implementation, integration, checks and fixes until the entire row is complete; partial rows remain LEFT. Do not stop or retire after a partial publication or an unresolved-reference/handoff note.

**Parallelize within each owned row — user direction, October 29:** the row owner actively identifies independent reference research, implementation, integration and dependency work and assigns it to fresh, focused agents so it proceeds concurrently with other research, coding, checks and review. Do not leave an independent investigation waiting for an unrelated increment to finish or publish. For example, recover document ownership while capture-to-Library is being implemented or reviewed. The original owner organizes the work, agrees scopes and interfaces directly with helpers, integrates their results and remains responsible for completing the entire fixed row; delegation does not split, reweight or prematurely complete it. Helpers coordinate directly with the owner and record durable handoffs. Use separate worktrees for independent source edits, retain the required independent review before publication, respect the shared nonblocking decompilation slots and dedicated engine owner, and continue other useful work if agent or tool capacity is unavailable. Reassess available parallel work and dispatch pending helpers as capacity opens; do not wait in a blocking queue or poll repeatedly. Cursor agents still must not call `move_agent_to_root` / `move_agent_to_cloned_root` when creating those worktrees; see the CRITICAL rule at the top of this file.

**Independent delivery and integration ownership — user direction, October 29:** do not hold a completed, checked and independently reviewed row from publication or completion because another owned row must integrate it. Publish the completed row directly; the consuming row's owner owns its integration, checks and any fixes needed there. Agree and record the concrete interface and handoff, and coordinate without making the producer wait for the consumer's delivery. Unowned required work remains the author's responsibility; partial work on the author's own row stays LEFT and continues through completion. This supersedes the October 28 instruction to keep a completed producer row open until a separately owned consumer integrates it.

Before changing this project, read `README.md` for the project/build overview and `docs/parity.md` for current progress, delivery order, durable user requirements, feature inventory, exclusions and completion rules. Re-read these after context compaction. They are part of the implementation workflow, not a finished-feature claim. New contributors, including Claude, must also read `docs/collaboration.md` before claiming or editing work. Coordination with contributors outside this Codex session happens through committed repository documents; chat-only decisions are insufficient.

**Documentation direction, October 25:** keep README concise: project overview, build entry points and at most one constantly updated current-state line. Put progress, remaining work, priorities and feature requests in `docs/parity.md`; do not duplicate them in README. Focused architecture/usage documents may explain their actual subsystem. Old README progress history remains recoverable in Git, not copied into another redundant report.



**Agent utilization and fresh context — user direction, October 28:** when an agent finishes its original assignment, terminate/close it when supported; otherwise interrupt and retire it permanently. Never reuse it for another assignment through `followup_task`, messages or another mechanism. Start a fresh agent with `fork_turns="none"` and a focused, self-contained brief using current instructions, exact paths and verified evidence. Continuing the same unfinished assignment is allowed. Keep family ownership and row handoffs in the parity ledger so fresh agents can continue without inherited transcripts. Each owner verifies and publishes its completed increments directly to main; root is not an integration gate. This supersedes older completed-agent reuse guidance.


**Review scope clarification — October 29:** if each increment has already been independently reviewed, do not repeat a whole-row or complete historical diff review at completion. Review the current increment's new and materially changed code, including untracked files and its integration with earlier reviewed increments. Previously cleared, unchanged code does not need a repeated review; material changes do. Row completion still requires appropriate checks and clearance of all new or changed source.

**Dedicated engine-owner exception — user direction, October 28:** retain and reuse the single Codex `engine_owner` agent for the engine-owner job every time. This is the only exception to completed-agent retirement; never repurpose it for feature work. It owns shared apply/build/seal/package, canonical source freezes and advances, stage receipts, pending-engine checks and engine documentation/publication. Root coordinates, supervises and reports progress; feature owners continue to publish their own work.

**Whole-family delivery, October 26:** each owner keeps one complete feature family through its remaining production behavior and essential presentation/interaction, using the existing parity breakdown and REA plus permitted appearance inspection. Publish coherent increments frequently, but do not call an increment a completed family or defer missing layouts, controls, focus behavior and transitions as optional polish. Keep a finite remaining checklist with the family; move to another family only after closure or explicit reprioritization. Each owner reconciles current main, completes the applicable checks, and commits and pushes its own work directly to main; root is not an approval or integration gate. The user explicitly overrides all Boulder instructions, including atomic-commit, review-gate and merge-workflow guidance. Preserve useful source review and checks, but do not wait for root or build an unpublished backlog. Current ownership and remaining work belong in the parity ledger, not README.

- **Helpers first; nonblocking REA slots — user direction, October 28.** Every agent starts with retained contracts/evidence and the recovered-components, cross-reference, Swift-type and annotated-function helpers below. Do not use direct REA or decompilation when those helpers answer the question. Before a direct call, state the specific unresolved question and why the helpers did not resolve it; do not decompile just to corroborate a helper result. Only two decompilation slots are available. Use the shared status and atomic nonblocking acquisition in `work/claude-sidebar-rea/rea-decompile`; if both are busy, continue independent source work, documentation or permitted checks and retry later. Never sit in a blocking slot queue or polling loop, bypass the shared pool with a heavy direct REA call, steal a live slot, or classify a long-running job as stale. Slot records identify owner, job and start time. Report a genuinely blocking dependency to the coordinator after independent work is exhausted.
- For runtime failures, establish a controlled reproduction and identify the failing delivery/state boundary before changing behavior. Keep independent reference mismatches separate from proven causes. If a correction leaves the original failure unchanged, stop adding behavior patches and improve the causal observation. Tests must reproduce the reported failure, not merely assert the proposed change. Keep tool-targeting limits distinct from app failures, and do not infer a priority change or permission to abandon work from a status question or frustration.
- Before interpreting native GUI input failures, verify the exact app/window owner and the OS active/key state required by that interaction. Indexed accessibility actions and synthetic clicks can reach a background window without normal user activation. Record the frontmost app when activation fails; a protected system authorization surface makes the run unsuitable for isolated input acceptance until it is resolved. Do not turn that test condition into a browser focus, visibility or click-replay patch.
- Finish the active feature batch through source, appropriate checks under the current user direction, documentation, commit and push before switching features. Put new reminders in the parity ledger or delegate bounded independent investigation.
- Keep the parity ledger current and update only the single README state line when needed. Mark implemented, runtime-verified and unresolved behavior separately. Full functionality, design, interaction and motion parity plus the dedicated deep polish pass are required before calling Parc finished.
- **Progress updates — corrected user direction, October 28:** every five minutes, finish the bounded checks, thinking and coordination first, then deliver one complete uninterrupted update at the end, without interleaving row updates with tools or further coordination. Report each active row in Claude's plain format: `ROW (name): previous% → current%. What changed. Actual current step.` Use the owner's estimated completion for that row; show one percentage until a previous estimate exists. Do not substitute family totals, repeat estimate disclaimers, or explain the reporting process. Announce publication and engine-stage outcomes promptly. The fixed family DONE/LEFT ledger still records only completed requirements; partial rows stay LEFT. Do not revisit completed rows merely because their old names remain on reused worktree directories.
- Keep only used source, focused tests and useful documentation in Git. Remove abandoned implementation. Build outputs, profiles, logs, raw REA output and dependency binaries are ignored local artifacts.
- Every commit must be immediately pushed to `origin` (`https://github.com/etsenake/parc.git`), with local and remote SHA checked before another commit. Do not leave an unpublished commit backlog. Keep completed engine changes and their dependent app source together in a Git worktree and push its commits to GitHub main while an earlier engine build runs. Only the engine rebuild is deferred: complete the same source reviews, compiler/component checks, integration validation and other currently authorized checks before delivery. The active build inputs stay unchanged; publication and further implementation must not wait for the build. Fast-forward the original main checkout to the published commits after the active engine is sealed and its in-flight app packaging is finished, then run the next required incremental build.
- If the user later reauthorizes functional browser tests, verify real HTTPS rendering and responsiveness alongside local fixtures. That permission is currently withdrawn. Do not infer full performance or visual parity from a short sample or passing unit tests.

**Whole-module Swift check (clarified October 29):** iterate with the fast `-typecheck`. Before closing a completed row with material Swift changes, run the whole-module check as `-emit-sil -Onone -o /dev/null` on its finished tree. Josh clarified that SIL is for closing whole rows, not for each partial increment. Partial increments still need appropriate checks and independent review before publication. SIL catches definite-initialization errors (for example `self` used before `self.init`) that `-typecheck` passes and release packaging refuses; v234's first packaging failed this way.

