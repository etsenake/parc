# Independent engine source bootstrap checks

`scripts/engine-source.py` prepares and builds pinned Chromium and applies
Parc's source-owned browser, window and extension integration through the reviewed
overlay. Use an explicitly selected workspace, preferably ignored `work/` inside
the checkout. App packaging is handled by `scripts/build.py`; this source tool
does not package or launch the app.

Run the offline safety suite from the repository root:

```sh
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s tests/EngineSource -v
```

The suite uses temporary files and mocked process/host boundaries. It does not run Git, download dependencies, compile Chromium, inspect real Keychain data or launch an application.

## Branch export and equivalence

`scripts/engine-overlay-export.py` reads committed Git objects from an authoring
branch above the exact Chromium source-lock commit. It first proves that the
branch matches the current manifest's computed output, then exports its residual
changes as sorted per-target patches and owned files in a new review directory.
It validates the candidate with the same `prepare_overlay` implementation and
compares bytes and modes again. Every branch change and current manifest target
participates; extra changes, missing files and changed executable bits fail.
Unchanged files outside that inventory have identical Git objects on both sides.
The working tree and engine workspace markers are never consulted or changed.

```sh
python3 scripts/engine-overlay-export.py \
  --repository /absolute/chromium-authoring/src --branch parc-integration \
  --manifest "$PWD/Engine/ParcHost/overlay.json" \
  --output /absolute/review-directory
```

Dependency contents such as FFmpeg and WebRTC live in separate Git repositories,
even when Chromium records their commits as gitlinks. Supply
an explicit committed base and branch for each affected dependency, for example
`--dependency third_party/ffmpeg=BASE..parc-integration`. The repository lives at
that prefix beneath `--repository`; its base must be an ancestor of its branch.
A recorded gitlink must match the dependency base. The current manifest's exact
before hashes also bind the relevant dependency base
bytes. This check proves source equivalence, not DEPS synchronization or the
provenance of unrelated dependency files. Omitting a dependency touched by the manifest refuses the export. Equivalence
covers only the supplied committed trees: supply every dependency carrying
authored changes, including changes the current manifest does not mention.
The tool never reads uncommitted files or guesses dependency revisions.

The output directory must be new and separate from the branch repositories.
The candidate keeps the manifest ID, version and build targets, uses local
`source_root: "manifest"` inputs, and contains no timestamps or checkout paths.
Identical committed inputs produce identical file contents and file modes.
The manifest integrator reviews and publishes the candidate; exporting does not
increment the overlay version or edit the canonical manifest. The existing
release pipeline continues to materialize pinned upstream plus overlay once.
Never apply branch changes and overlay patches to the same source workspace.

The existing validator remains authoritative: deletions, renames with removed
sources, mode changes, binary/symlink entries and contextless rewrites cannot be
represented. They are refused. New owned files have mode 0644; patched files
preserve their base mode. Missing final newlines are preserved. Empty residuals
are subject to the validator's existing empty-overlay refusal.

## Engine workspace operations

Read-only preflight and command plan (the parent directory must already exist):

```sh
python3 scripts/engine-source.py check --workspace /absolute/engine-workspace
python3 scripts/engine-source.py plan --workspace /absolute/engine-workspace
```

When storage is ready and a full source download/build is authorized:

```sh
python3 scripts/engine-source.py sync --workspace /absolute/engine-workspace
python3 scripts/engine-source.py plan --for build --workspace /absolute/engine-workspace
python3 scripts/engine-source.py build --workspace /absolute/engine-workspace
```

`sync` claims a new directory or resumes an unchanged dependency-sync failure.
It fetches the two locked repositories, verifies origins and pinned files,
synchronizes Chromium dependencies and runs hooks with depot auto-update off.
`generate` writes explicit reviewed GN arguments and `build` compiles the Parc
framework/helper targets plus applied overlay targets. Repeated builds preserve
source and objects. Unrecorded changes are refused without reset, clean or stash.

`overlay-check` performs validation and in-memory transformation without changing
source files. Under the operation lock it can record a dead generation operation
as failed before validating the workspace. Both commands require a completed
owned workspace, its unchanged source fingerprint, the matching pinned
Chromium commits, and the exclusive operation lock. They do not download or
build anything. Every source input, contextual patch and resulting target is
SHA-256 bound. A mismatch anywhere prevents all source writes. Existing source
changes require exact unified-diff context and before/after hashes; there is no
fuzzy matching, binary patching, rename or executable-mode change. New files use
the manifest's `files` array. Inputs and targets must be regular UTF-8 text
without NUL, at most 8 MiB each, with confined paths and no symlinks. Repository
metadata, dependency selection, output directories and pinned bootstrap scripts
cannot be overlay targets.

The manifest schema is `schema_version: 1`, `id`, positive integer `version`, `upstream: {chromium: commit}`, `files`, `patches`, and optional `build_targets`. A file entry has `source`, source `sha256`, and `target` relative to `chromium/src`. A patch entry has `source`, patch `sha256`, and a `files` array of exact `target`, `before_sha256`, `after_sha256` entries. Each target appears once across the complete manifest. Optional `source_root: "repository"` makes inputs relative to this Parc repository and requires the manifest to be inside it; the default `"manifest"` makes inputs relative to the manifest directory. Neither mode accepts `..`. Build targets are qualified `//parc/...:target` GN labels, not arguments or shell commands.

Applying records the manifest identity, original text/modes, expected output hashes, target list and resulting workspace fingerprint. Reapplying the same manifest is a verified no-op. A deliberate update keeps the same ID and increments the version; its complete replacement recipe is applied against recorded originals, after checking the previous live outputs. Retired modifications restore their original text. Retired files are removed only when they were created by the previous overlay and still match its recorded output. Other source is preserved. An update leaves identical bytes and modes untouched, retaining inode and timestamps so local Siso checks do not rebuild their dependents unnecessarily. Changed source writes use atomic replacement; an ordinary error rolls back prior file contents. Process interruption leaves phase `overlay-applying` with `pending_overlay` set; re-running `overlay-apply` with the same reviewed manifest finishes the writes and clears that stage. A different pending manifest must not be substituted. This is not a multi-file filesystem transaction. Original text remains in immutable workspace-local records. An update requires regeneration before compiling, and generation must leave all reviewed overlay outputs unchanged or the compiler will not run.

The default is Release ARM64 component build, `symbol_level=0`, `enable_dsyms=false`, and local execution. Choose `--symbol-level 1` on both initial sync and later build for minimal backtrace symbols. `--jobs` defaults to four. No remote builder or paid service is configured. Symbol level zero loses debugging detail; this is an integration build, not the final distribution recipe.

Storage guards come from the `storage` section of [the source lock](../../Engine/source-lock.json). Preflight requires its configured free-space thresholds before sync and compilation. These are working floors, not guarantees that a build will fit. `plan` prints blockers but succeeds so its proposed commands can be reviewed; `check`, `sync` and `build` return status 2 on blocked preflight. Execution rechecks capacity before mutation. No automatic cleanup occurs.

A failed gclient dependency-sync records the partial repository inventory and source fingerprint.
Repeating `sync` validates that unchanged state, then resumes at gclient without reinitializing,
checking out, resetting or deleting existing repositories. A returned project-generation error
likewise records its source fingerprint and `generation-failed` phase, provided all applied overlay
outputs still match. An unchanged retry can regenerate; a reviewed overlay update can correct a
source issue before regeneration. A bootstrap error occurs before generation begins and preserves
the previous phase. After acquiring the operation lock, the tool converts a dead project-generation
receipt into a resumable failure and revalidates the source fingerprint before retrying. The
shipping path does the same for dead generation/build operations. Interrupted initial Git bootstrap,
incomplete dependency sync, runhooks failures and generation that changes reviewed overlay outputs
still require inspection; the tool preserves their files and refuses to guess a safe repair. Failed
compilation can be retried if source fingerprints still match. One operation per workspace is
enforced by an exclusive advisory lock. Source paths and their ancestors must not be symlinks;
unsupported characters are rejected because upstream-generated commands do not uniformly support
them.

The offline suite covers contextual transformations, rollback, update retirement,
locking, interrupted-operation recovery and build-target binding with temporary
files and mocked command execution. The production build and packaging workflow
is documented in [Engine](../../Engine/README.md) and
[packaging](../Packaging/README.md).
