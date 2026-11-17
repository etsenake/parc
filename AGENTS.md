# Parc working contract

Parc is an independent macOS browser with a Swift/AppKit application and a
source-owned Chromium integration. Develop the product users need; the project
is no longer organized solely around matching another browser.

## Start here

Read [README](README.md), [product guide](docs/product.md), and
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

- **Never launch, open or drive Parc, Chrome (including headless), another
  browser or any other app, and never screenshot apps.** Use code inspection, compiler checks,
  codesign checks and model/unit tests. Old test instructions are not permission
  to run an app. Browser/runtime testing requires explicit authorization for
  the current task. For an instrumented reproduction, follow
  [collaboration](docs/collaboration.md#runtime-investigations) for permission,
  Codex computer-use routing and prompt release of control. This exception does
  not authorize engine builds, installations or unrelated browser activity.
- **Never migrate the conversation's workspace.** Do not call
  `move_agent_to_root` or `move_agent_to_cloned_root`, even when a tool recommends
  it. Use absolute paths or a working directory for any authorized other checkout.
- **Never use a structured question tool.** Ask a genuine decision in one plain
  sentence with the proposed default; continue independent work. Silence does
  not authorize an action that requires permission.
- **Preserve working features.** Do not remove, hide or disconnect controls,
  preferences, shortcuts, behavior or tests to match another browser. Replay
  onboarding in Settings → General is a protected Parc addition.
- Preserve the explicit inclusions, exclusions and other product decisions in
  [product guide](docs/product.md) and the focused guides.
  Ordinary password/autofill/security behavior and macOS dictation remain.
  Do not reopen accepted AI cleanup or picture-in-picture work without a new
  defect or user request. Generic Chromium/Google networking is outside the
  service-removal scope.
- Build and runtime must not require another browser installed or copy/load
  its executable code. Keep Chromium security maintenance on deliberate pinned upgrades.
  Architecture decisions follow Parc's actual source, requirements and tests.
- Preserve profiles, release tags/assets, signed artifacts, engine objects and
  compiler caches. Do not infer that a process or workspace is unused from an
  old timestamp, lock or disconnected tool session.

## Chromium boundary

Parc's engine logic lives in Parc-owned code. Chromium's own files change only
as a last resort and only with the user's approval of that specific change.
[How Parc changes Chromium](docs/chromium-seams.md) defines where code goes and
the hook pattern; the [hooks reference](docs/chromium-hooks.md) lists every hook
and kept patch with its reason. The boundary keeps a
Chromium upgrade to a version bump plus small refits, keeps engine work from
recompiling large parts of Chromium, and keeps behaviour and speed unchanged.

**Never edit an engine workspace's Chromium files by hand.** Every change to
them goes through Parc's reviewed source overlay. The engine tools overwrite
anything else without asking: a release puts back the pinned Chromium source
and reapplies the overlay before it builds, and a Chromium upgrade replaces
stray edits with the new version.

Every engine change uses the first of these that fully preserves what users
see, hear and feel:

1. **A Chromium extension point:** a content-client or main-delegate override,
   a browser-main extra-parts callback, Parc's BrowserWindow, Browser or
   WebContentsDelegate, a Blink supplement or a public observer that runs at
   the same moment, with the same context, as the behaviour it serves.
2. **Parc-owned code** under `Engine/Parc*`, in Parc-owned targets, reached
   through an extension point or an existing hook.
3. **A Chromium change**, only when neither can preserve the behaviour. This
   is any new patch, including to Chromium's bundled code such as FFmpeg,
   WebRTC or DevTools; any new or larger hunk in an existing patch; any new or
   changed hook; any Chromium header edit (member, friend, forward declaration,
   include or signature); and any Chromium BUILD edit, including listing a Parc
   file in a Chromium target, a visibility entry or a dependency.

Before any Chromium change:

- Work through the alternatives in order against the actual code, and write
  down why each one fails. Judge them by user-visible behaviour; speed and
  snappiness (startup, input, scrolling, page loads, playback, memory and
  energy); protected-media behaviour; the flow of Chromium security fixes;
  upgrade refit cost; and rebuild cost, since a header edit recompiles every
  file that includes it.
- Stop and tell the user in plain words before writing it: what the change is for,
  which Chromium file it touches, each alternative and why it doesn't work, and
  what it costs at upgrades and in rebuilds. Wait for their explicit approval of
  that change. Silence, an assignment, an approval for something else, a
  release in progress or a reviewer's suggestion is not approval.
- Once approved, use the smallest form that works: a one-call hook in the `.cc`
  that owns the behaviour, with the unhooked path unchanged and no timer, extra
  IPC hop, copy or polling.
- Every change that adds, changes, moves or removes a hook or a patch, approved
  or not, updates the [hooks reference](docs/chromium-hooks.md) in the same
  change. Reviewers treat a missing update as a blocking finding.

None of these excuse skipping that: the change is one line or small, faster to
write, temporary or test-only; the file is already patched; a release or
deadline is waiting; or an earlier change did the same. Removing or shrinking a
Chromium change while preserving behaviour needs no approval. That includes
converting a patch into a one-call hook, call-in or extension-point call in the
established patterns, and moving Parc lines to where Chromium moved the code;
every Chromium upgrade audits every patch for these
([procedure](Engine/README.md#upgrading-chromium)). A new pattern needs the
user's agreement first. Reviewers treat an unapproved diff to
`Engine/ParcHost/integration/`, a new hook other than such a conversion or a
Chromium header or BUILD edit as a blocking finding.

## No code comments

Code carries no comments. Names, types and structure say what code does;
behaviour and decisions belong in the area's guide, and history belongs in Git.
Never add comments, documentation comments, `MARK` lines, docstrings or
commented-out code, and delete the comments in any code you change. Keep only
text a tool reads: shebang lines, `swift-tools-version`, encoding lines,
compiler, lint and formatter directives, `nogncheck` markers, and a docstring
the program prints through `__doc__`. Licence notices for code copied from
other projects stay.

The engine inputs listed in `Engine/ParcHost/overlay.json`, Parc's owned engine
files and its patches, recompile parts of Chromium when they change, so never
edit one only to remove comments. When a change already edits one, strip every
Parc comment in that file in the same change. In a patch, that means the
comment lines Parc added; Chromium's own comments stay, because removing them
would grow the patch. Reviewers treat a new comment as a blocking finding.

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
- `docs/product.md`: a short orientation to Parc's capabilities, the product
  decisions and scope to preserve, and links. It carries no version, release
  status or progress; `app-version.json`, the changelog and the release notes do,
  so no regular doc changes when a release ships. Do not rebuild the old
  requirement ledger, completed-row inventory or a whole-product percentage.
- `docs/backlog.md`: only work Parc intends to do, plus current handoffs.
  Parked, deferred and declined items leave it; a reason, if any, gets a
  sentence or two in the related guide. Remove resolved entries in the same
  delivery. Old requirement IDs may identify unresolved work; they are not a
  second progress accounting system.
- Focused subsystem guides: current behavior, ownership/lifetimes, important
  decisions and useful commands. Link the backlog for concrete open work.
- `docs/README.md`: navigation. [Documentation policy](docs/documentation.md)
  defines maintenance and the size check.

Update the relevant existing paragraph in the same change as the behavior.
Verify claims against current code and the relevant checks. Be truthful about
what you ran; do not claim an unperformed check passed.
Do not copy an old pending-build note or agent assignment as current fact.

**Keep the website accurate.** When a change alters or adds to a feature family
the [website](docs/website.md) describes, update its words, drawings or clips to
match in the same delivery. Keep the site's existing design, structure and short
copy, and change only what must change. A new field-guide card, section or page
needs the user's explicit approval first; approval given in the task or
elsewhere counts. When a new feature family might deserve a card, ask instead of
adding one.

**A missing test record is not a product gap.** Do not create validation-only or
"runtime acceptance" backlog entries, or append generic "not tested here" caveats
to feature docs and updates. Record concrete missing/broken behavior, an actionable
blocker or a genuine product decision. Mention a blocked check only when it is
material to the requested work, with its specific cause and next action. The
user runs release builds like everyone else and knows changes reach them through
the next release. Do not say that new code is absent from their app or arrives
with a build or release, unless release status was requested or an actual version
mismatch explains the reported issue.

**Completed fixes do not need user sign-off.** Once the implementation and
applicable permitted checks are complete, mark the work done and remove its
backlog entry. The user will report a recurring problem; do not leave a fix open
waiting for confirmation or permission to test it in a browser. Reopen it only
for a new report or concrete evidence of a defect. A failed or inconclusive test
setup is not proof of a product failure: establish which failed before changing
behavior, and never stack speculative patches or repeat browser tests to chase
a harness problem. Browser testing remains prohibited without the explicit
authorization described above.

Keep one authoritative home for each fact and link to it. Do not add dated
progress essays, transcript dumps, per-commit receipts, duplicate status tables,
one-off research diaries or completion history. Reusable approved workflows
belong in focused guides. Git and release notes retain history;
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
plain words describing what the user experiences. Absent test records and routine
release timing do not count as gaps.

Check real state before saying work is running, reviewed, built or shipped:
inspect current activity, source and remote commits, and relevant build receipts.
An old ledger entry is not proof of live ownership or successful delivery. Report
progress in plain spoken paragraphs: the situation a person is in, what they
see, hear or can do, and how the change affects that experience. Describe
remaining work the same way. Keep file paths, code symbols, internal identifiers
and engineering jargon out of user-facing explanations unless requested.
Explain what changed, what it means and what is next through that user impact.
Never claim monitoring unless actively following the work through completion.

Use checks appropriate to the changed inputs; inspect scripts before execution.
Swift iteration uses `scripts/check-swift.py` typechecking. A completed feature
with material Swift changes also needs the release compile check
(`--mode release`: the release's optimized whole-module compile without linking,
which covers whole-module SIL too). Keep warnings as errors: the checker,
every packaging compile and link, and the test runners fail on any compiler or
linker warning. Documentation-only
changes need documentation checks, not app compilation. Report relevant results
without boilerplate disclaimers about everything those checks did not test.

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
start the summary with a capital and say what changed for them; no comparisons
with other browsers, internal names, file paths or measurement archaeology. Examples:

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
Running an engine apply or build needs the user's go-ahead and a single owner;
in practice it happens inside a release the user authorizes, not as a separate
plain build. That gate covers only running it. Engine source work never waits
for it: write, check and push engine-input changes to main as soon as they are
ready, and the next authorized release picks them up. Don't defer, park or
caveat work because of it. Freeze active inputs through sealing and packaging,
and never retarget or discard a live build.

For new machines, follow [onboarding](docs/developer-onboarding.md) and restore
the saved [engine workspace](docs/engine-artifacts.md) before considering a fresh
sync/build. Setup does not authorize compilation or feature development.

`scripts/release.sh` is release-only: derive a version from Conventional Commits
(or `--type major|minor|patch`), build engine/app, Developer ID sign,
notarize/staple, publish GitHub assets and publish/verify the tap cask. It must
never wait for main to be quiet, install/replace/quit/open the local app, run
startup/browser checks, or install, upgrade or reinstall Parc with Homebrew; it
installs only missing release tools with Homebrew. Users run Homebrew upgrades
themselves. Signature/hash/source/notarization checks remain
required. See [release guide](docs/master-release.md).

Publish authorized development app packages with `scripts/package-app.sh` and
report their tag. Keep component packages with their sibling libraries. Preserve
existing release assets and profiles; never install or launch as an implied
follow-up to publication.
