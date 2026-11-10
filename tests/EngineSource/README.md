# Independent engine source bootstrap checks

This tool prepares and builds **pinned upstream CEF/Chromium** in an explicitly selected external workspace. It does not implement the required Parc browser/window/extension bridge, package a replacement app, or launch anything. Stock embedded CEF does not satisfy Parc's extension/native-shell architecture gate.

Run the offline safety suite from the repository root:

```sh
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s tests/EngineSource -v
```

The suite uses temporary files and mocked process/host boundaries. It does not run Git, download dependencies, compile Chromium, inspect real Keychain data or launch an application.

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

`sync` initially requires a **new directory**; a subsequent invocation may resume an owned, unchanged dependency-sync failure. It creates an ownership marker and workspace tmp directory, preserves the real HOME, fetches the three locked repositories, verifies revisions/origins and script hashes, synchronizes pinned Chromium dependencies without hooks, applies CEF's verified runhooks source patch, then runs hooks. CEF uses full commit ancestry for its version generator; Chromium and depot_tools use shallow pinned fetches. The selected dependency versions come from the pinned Chromium DEPS, without automate-git's moving `siso_version=latest` override. Depot auto-update is disabled. There is no shell command interpolation or arbitrary passthrough argument.

`build` accepts only that workspace, lock and source fingerprint. Before generating CEF projects, it runs the pinned depot_tools `ensure_bootstrap` to initialize its bundled Python without updating the depot_tools checkout. `gclient` can work through vpython while GN's separate Python entry point is still missing, so a successful sync alone does not establish this prerequisite. The tool records the resulting upstream source patches, then invokes `autoninja -C out/Release_GN_arm64 -j 4 cef_framework` plus any applied overlay's reviewed build targets. The macOS framework target includes the engine and its runtime resources; the broader upstream `cef` group additionally builds example apps and large test executables that this integration build does not need. Once generation succeeds, a repeated build runs only autoninja after validation. Unrecorded changes to tracked source, dependency HEADs or untracked inputs are refused and preserved; no reset/clean/stash is performed. Ordinary build validation uses the saved dependency inventory rather than walking the full source tree. Source-owned bridge changes enter through the reviewed overlay step below. Do not work around this protection by overwriting the marker.

After sync completes, inspect and apply the whole reviewed source overlay:

```sh
python3 scripts/engine-source.py overlay-check --workspace /absolute/engine-workspace --manifest /absolute/Parc/Engine/ParcHost/overlay.json
python3 scripts/engine-source.py overlay-apply --workspace /absolute/engine-workspace --manifest /absolute/Parc/Engine/ParcHost/overlay.json
```

`overlay-check` performs the complete validation and in-memory transformation without writing files. Both commands require a completed owned workspace, its unchanged source fingerprint, the matching pinned CEF/Chromium commits, and the exclusive operation lock. They do not download or build anything. Every source input, contextual patch and resulting target is SHA-256 bound. A mismatch anywhere prevents all source writes. Existing source changes require exact unified-diff context and before/after hashes; there is no fuzzy matching, binary patching, rename or executable-mode change. New files use the manifest's `files` array. Inputs and targets must be regular UTF-8 text without NUL, at most 8 MiB each, with confined paths and no symlinks. Repository metadata, dependency selection, output directories and pinned bootstrap scripts cannot be overlay targets.

The manifest schema is `schema_version: 1`, `id`, positive integer `version`, `upstream: {cef: commit, chromium: commit}`, `files`, `patches`, and optional `build_targets`. A file entry has `source`, source `sha256`, and `target` relative to `chromium/src`. A patch entry has `source`, patch `sha256`, and a `files` array of exact `target`, `before_sha256`, `after_sha256` entries. Each target appears once across the complete manifest. Optional `source_root: "repository"` makes inputs relative to this Parc repository and requires the manifest to be inside it; the default `"manifest"` makes inputs relative to the manifest directory. Neither mode accepts `..`. Build targets are individual simple GN names, not arguments or shell commands.

Applying records the manifest identity, original text/modes, expected output hashes, target list and resulting workspace fingerprint. Reapplying the same manifest is a verified no-op. A deliberate update keeps the same ID and increments the version; its complete replacement recipe is applied against recorded originals, after checking the previous live outputs. Retired modifications restore their original text. Retired files are removed only when they were created by the previous overlay and still match its recorded output. Other source is preserved. An update leaves identical bytes and modes untouched, retaining inode and timestamps so local Siso checks do not rebuild their dependents unnecessarily. Changed source writes use atomic replacement; an ordinary error rolls back prior file contents. Process interruption leaves phase `overlay-applying` with `pending_overlay` set; re-running `overlay-apply` with the same reviewed manifest finishes the writes and clears that stage. A different pending manifest must not be substituted. This is not a multi-file filesystem transaction. Original text remains in immutable workspace-local records. An update requires regeneration before compiling, and generation must leave all reviewed overlay outputs unchanged or the compiler will not run.

The default is Release ARM64 component build, `symbol_level=0`, `enable_dsyms=false`, and local execution. Choose `--symbol-level 1` on both initial sync and later build for minimal backtrace symbols. `--jobs` defaults to four. No remote builder or paid service is configured. Symbol level zero loses debugging detail; this is an integration build, not the final distribution recipe.

Storage guards come from the `storage` section of [the source lock](../../Engine/source-lock.json). Preflight requires its configured free-space thresholds before sync and compilation. These are working floors, not guarantees that a build will fit. `plan` prints blockers but succeeds so its proposed commands can be reviewed; `check`, `sync` and `build` return status 2 on blocked preflight. Execution rechecks capacity before mutation. No automatic cleanup occurs.

A failed gclient dependency-sync records the partial repository inventory and source fingerprint. Repeating `sync` validates that unchanged state, then resumes at gclient without reinitializing, checking out, resetting or deleting existing repositories. A returned project-generation error likewise records its source fingerprint and `generation-failed` phase, provided all applied overlay outputs still match. An unchanged retry can regenerate; a reviewed overlay update can correct a source issue before regeneration. A bootstrap error occurs before generation begins and preserves the previous phase. Interrupted initial Git bootstrap, terminated processes that could not record their state, runhooks failures and generation that modifies reviewed overlay outputs remain incomplete and require inspection; this tool does not guess a safe repair. Their files remain intact. Failed compilation can be retried if source fingerprints still match. One operation per workspace is enforced by an exclusive advisory lock. Source paths and their ancestors must not be symlinks; unsupported characters are rejected because upstream-generated commands do not uniformly support them.

The offline suite verifies the Python tool, contextual transformations, rollback, update retirement, locking and build-target binding with temporary files and mocked command execution. It does not establish that a particular native bridge compiles or works. Actual upstream sync/build status is recorded separately in the project README; no independent Parc engine runtime claim follows from these tests.
