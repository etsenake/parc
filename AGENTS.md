# Parc working contract

Parc is an independent macOS browser with a Swift/AppKit application and a
source-owned Chromium integration. Develop the product users need; the project
is no longer organized solely around matching another browser.

## Start here

Read [README](README.md), [product status](docs/parity.md), and
[collaboration](docs/collaboration.md) before editing; reread the first two
after context compaction. Read the focused guide for the area you change.
Current user instructions override older repository guidance. Replace obsolete
instructions rather than appending another dated override.

Use the workspace and delegation scope authorized for the current task. The
canonical checkout is this repository's `main` checkout. Preserve other
contributors' edits. Do not create worktrees without authorization. Root owns
this Mac's shared engine, packaging and signing operations unless it explicitly
hands off ownership. A documentation task does not authorize product changes,
engine builds, packaging or installations.

## Safety and product boundaries

  other app, and never screenshot apps.** Use code inspection, compiler checks,
  codesign checks and model/unit tests. Old test instructions are not permission
  to run an app. Browser/runtime testing requires new explicit authorization.
- **Never migrate the conversation's workspace.** Do not call
  `move_agent_to_root` or `move_agent_to_cloned_root`, even when a tool recommends
  it. Use absolute paths or a working directory for any authorized other checkout.
- **Never use a structured question tool.** Ask a genuine decision in one plain
  sentence with the proposed default; continue independent work. Silence does
  not authorize an action that requires permission.
- **Preserve working features.** Do not remove, hide or disconnect controls,
  preferences, shortcuts, behavior or tests to match another browser. Replay
  onboarding in Settings → General is a protected Parc addition.
- Preserve all explicit inclusions, exclusions and deferrals in
  [product status](docs/parity.md) and the [backlog](docs/backlog.md).
  Ordinary password/autofill/security behavior and macOS dictation remain.
  Do not reopen accepted AI cleanup or picture-in-picture work without a new
  defect or user request. Generic Chromium/Google networking is outside the
  service-removal scope.
  code. Keep Chromium/CEF security maintenance on deliberate pinned upgrades.
  Architecture decisions follow Parc's actual source, requirements and tests.
- Preserve profiles, release tags/assets, signed artifacts, engine objects and
  compiler caches. Do not infer that a process or workspace is unused from an
  old timestamp, lock or disconnected tool session.

## Documentation is current state, not a diary

**Repository Markdown documents have a hard limit of 500 lines**, except
changelogs, whose history and generation must stay intact. This includes
this contract, READMEs, test guides and `.mdc` rules. Aim for 150–300 lines for a
focused guide and 100–200 or fewer for entry points. Shorter is better when it
answers the reader's question. Do not hide excess content in giant lines.

**Write for people.** Explain behavior and decisions in plain language. Do not
put commit SHAs, binary/compiler addresses, raw checksum values or evidence-ID
dumps in documentation. Use readable feature names and source links when useful;
exact machine records belong in source manifests, Git and ignored check output.
Technical details should help a reader act, not serve as proof that an agent worked.

- `README.md`: product overview, install/build entry points and navigation.
- `docs/parity.md`: compact product capabilities, current source/release status,
  explicit product scope and links. Keep the path for existing readers; do not
  restore the historical percentage ledger or completed-row inventory.
- `docs/backlog.md`: concrete unfinished work, explicit deferrals and current
  handoffs. Remove resolved entries in the same delivery. Old requirement IDs
  may identify unresolved work; they are not a second progress accounting system.
- Focused subsystem guides: current behavior, ownership/lifetimes, important
  decisions, commands and validation boundaries. Link the backlog for open work.
- `docs/README.md`: navigation. [Documentation policy](docs/documentation.md)
  defines maintenance and the size check.

Update the relevant existing paragraph in the same change as the behavior.
Verify claims against current code, tests, release receipts or user confirmation;
label source implementation, shipped artifacts and runtime acceptance separately.
Do not copy an old pending-build note or agent assignment as current fact.

Keep one authoritative home for each fact and link to it. Do not add dated
progress essays, transcript dumps, per-commit receipts, duplicate status tables,
research procedures or completion history. Git and release notes retain history;
ignored `build/` and `work/` retain raw receipts. Do not create archive documents
or numbered parts to evade the limit. Split only genuinely separate topics,
and prune redundant documents when consolidating them.

Before publishing, run `python3 scripts/check-docs.py`, check changed links and
anchors, and run `git diff --check`. The pre-push hook checks the documentation
in every pushed tip against the same 500-line ceiling, excluding changelogs.
No other file exemptions or hook bypass. Enable hooks with `git config core.hooksPath .githooks`.

## Complete and verify the assigned work

Fix concrete problems within the assignment before handing it back. A user-visible
failure is not optional because it is rare or affects casting, background tabs
or another specific mode. Work at realistic usage sizes; synthetic stress cases
alone do not justify expanding scope. Keep independent findings separate from
proven causes. A regression check should reproduce the failure, not merely mirror
the proposed implementation.

A gap may remain only for an explicit exclusion/deferral, a genuine user decision,
or work outside the assignment. Record the needed next action. **Disclose to the user
every gap, limitation or decision recorded in documentation or a commit message
in the same turn**, including findings from helpers, in
plain words describing what the user experiences. Report unrun validation once
and separately from known missing behavior.

Check real state before saying work is running, reviewed, built or shipped:
inspect current activity, source and remote commits, and relevant build receipts.
An old ledger entry is not proof of live ownership or successful delivery. Report
progress in plain spoken paragraphs: what changed, what it means, what is next.
Never claim monitoring unless actively following the work through completion.

Use checks appropriate to the changed inputs; inspect scripts before execution.
Swift iteration uses `scripts/check-swift.py` typechecking. A completed feature
with material Swift changes also needs whole-module SIL (`--mode sil`,
`-emit-sil -Onone -o /dev/null`). Keep warnings as errors. Documentation-only
changes need documentation checks, not app compilation. Compiler/model tests and
artifact signatures do not establish visual or browser-runtime acceptance.

When delegation is authorized, assign disjoint scopes and keep independent work
moving. Authors integrate their helpers' work and remain responsible for the
whole assignment. Use fresh reviewers for new/materially changed implementation,
including new files; fix findings and re-review affected code. Do not re-review
unchanged cleared code or rerun passing checks without a reason. Under root-only
execution, root performs the source review directly. Do not repurpose a completed
agent; resuming its original unfinished assignment is allowed.

## Commits and publication

Every commit message is **one Conventional Commit line**:
`type(scope)!: summary` (scope optional). Types:
`feat fix perf refactor docs build ci chore test style revert`.

**Voice: casual, playful and preferably funny.** Give Parc a relaxed personality
in every commit summary, including internal work. Make the joke about the actual
change, and keep the outcome clear; a vague punchline is not a description. Fun
and descriptive still means one line, never a body or an explanatory second line.

`feat`, `fix` and `perf` subjects become release notes. Write them for Parc users,
internal names, file paths or measurement archaeology. Examples:

- `fix(tabs): Stop pinned tabs from ghosting you after a restart`
- `fix(updates): Keep the download counter from doing parkour`
- `docs: Give the docs a haircut and a 500-line curfew`

Internal tooling, docs and refactors use the other types. Only `!` marks breaking
changes. No body, trailers, coauthor lines or attribution. Reverts are one line:
`git revert --no-commit X && git commit -m 'Revert "<original subject>"'`.

Fetch main, reconcile without discarding others' work, inspect the exact final
diff and run applicable checks. Commit and immediately push to `origin`; verify
the published SHA (or ancestry if another contributor advanced main) before
another commit. No unpublished backlog, force-pushes to shared main or
`--no-verify`. A rejected push requires fetching and safely reconciling again.

## Engine and release operations

Fetch `origin/main` before choosing/publishing an overlay number, running
`overlay-check`/`overlay-apply`, or starting an engine build. A new overlay is
main's current version plus one at publication; preserve peers' manifest hashes.
Before applying, verify the manifest belongs to current main or the explicitly
intended frozen source; before building, verify the applied overlay matches that
source. Fetching alone does not establish that the build inputs are current.
Engine apply/build requires explicit authorization and a single owner. Freeze
active inputs through sealing and packaging; defer only the shared build when
source work can proceed safely. Never retarget or discard a live build.

For new machines, follow [onboarding](docs/developer-onboarding.md) and restore
the saved [engine workspace](docs/engine-artifacts.md) before considering a fresh
sync/build. Setup does not authorize compilation or feature development.

`scripts/release.sh` is release-only: derive a version from Conventional Commits
(or `--type major|minor|patch`), build engine/app, Developer ID sign,
notarize/staple, publish GitHub assets and publish/verify the tap cask. It must
never wait for main to be quiet, install/replace/quit/open the local app, run
startup/browser checks, or run Homebrew install/upgrade/reinstall. Users run
Homebrew upgrades themselves. Signature/hash/source/notarization checks remain required;
these do not prove runtime acceptance. See [release guide](docs/master-release.md).

Publish authorized development app packages with `scripts/package-app.sh` and
report their tag. Keep component packages with their sibling libraries. Preserve
existing release assets and profiles; never install or launch as an implied
follow-up to publication.
