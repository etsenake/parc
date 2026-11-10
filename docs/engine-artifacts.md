# Existing engine snapshots

## Finish an upload without a chat session

`scripts/publish-engine-snapshot.py --config /absolute/publish-config.json
--background` starts a detached process. Use the same command to resume after a
failure; a lock prevents duplicate publishers. Add `--status` instead of
`--background` to read progress. `publisher.log`, `capture.log` and
`publisher-state.json` are written beside the config.

Run the command from any directory when using absolute script/config paths.
`--check` verifies GitHub access without starting work. Authentication is checked
before a background process starts. If an inherited `GH_TOKEN` or `GITHUB_TOKEN`
is invalid (HTTP 401), the runner tries the existing saved GitHub login and
removes the invalid overrides only from its own process and children if that
login succeeds. It does not edit shell configuration or save credentials.

The JSON config supplies `workspace`, `package`, `assets`, `repository`,
`release`, `source_revision` and `publish_git` (boolean). The release must
already exist. Set `publish_git` to true only in a clean, dedicated checkout
authorized to commit the final `Engine/engine-artifacts.json` and push main.
The runner preserves a live capture, reuses complete archives and matching
uploaded chunks, verifies both archives, then publishes the final pin. An
interrupted compression stream must be recreated; unchanged uploaded chunks
are reused. Mismatching partial workspace chunks may be replaced only while
no final workspace manifest has been published. Completed archives and the
application package are never overwritten. No engine build is run.

Keep the Mac awake and connected while it runs. If status says `STOPPED`, read
the log and rerun the same command after resolving the reported problem.

## Restore the saved artifacts

The private release stores the **existing incremental workspace** and the **last
completed development package** separately. Restoring the workspace preserves
source repositories, toolchains, object files and Siso build state. Its captured
receipt may describe an unfinished build; the snapshot does not turn it into a
completed engine. The development package includes `Parc.app`, its sibling
engine libraries and its original `package-report.json`.

Use Python 3.12 or later and authenticate GitHub CLI with access to
`etsenake/parc`. The release and SHA-256 identities are pinned in
`Engine/engine-artifacts.json`. Git pull updates that pin without automatically
downloading or replacing local files.

The pin's `source_revision` identifies a Parc commit whose engine inputs match
the snapshot and which contains these restore tools. If a future checkout has
a different source lock or overlay, restore from a separate checkout of that
revision, preserving your current work. Pass `--lock` with the absolute path to
`Engine/engine-artifacts.json` in your original checkout; the pinned source
commit predates that release pin. Apply later engine changes through the
normal overlay workflow; do not alter the snapshot's receipts to bypass a
mismatch. When the only lock difference is `build.gn_defines`, run
`engine-source.py reconfigure` with the snapshot's lock after restoring (see
[engine commands](../Engine/README.md#build-configuration)).

## Download and restore

Choose new absolute destinations whose parents already exist. Prefer ignored
paths inside this checkout (`work/` for the engine workspace, `build/` for
packages). Paths must have no spaces.

```sh
mkdir -p "$PWD/work" "$PWD/build" "$PWD/build/artifact-cache"
python3 scripts/engine-artifacts.py fetch --kind workspace \
  --cache "$PWD/build/artifact-cache"
python3 scripts/engine-artifacts.py restore --kind workspace \
  --cache "$PWD/build/artifact-cache" \
  --destination "$PWD/work/engine"
python3 scripts/engine-artifacts.py fetch --kind package \
  --cache "$PWD/build/artifact-cache"
python3 scripts/engine-artifacts.py restore --kind package \
  --cache "$PWD/build/artifact-cache" \
  --destination "$PWD/build/restored-development"
```

Keep the complete development directory together. Its component libraries are
required beside `Parc.app`; copying the app alone is insufficient. This command
restores the previously completed package without compiling or signing it.

Workspace restore validates its recorded source lock, overlay, source
fingerprint and toolchain inventory, adopts the new absolute path, and retains
the original receipt in snapshot metadata. It preserves source/object timestamps
and cache files. Machine-local SDK/log symlinks are recorded as exclusions.
Relocation invalidates the old generated build graph: adoption records `synced`
and requires normal generation before another build. No source or binary text
is rewritten, and no build is launched by restore. See
[engine commands](../Engine/README.md) before making engine changes. A different
workspace depth or Xcode installation may invalidate generated dependencies;
this snapshot preserves reusable output but does not promise a zero-work build.

Fetch resumes `.partial` downloads and reuses verified parts. It refuses to
replace an existing changed cache entry. `verify --kind workspace|package
--cache /absolute/cache` checks the cached bytes without restoring. Restore
verifies every archive entry and publishes a new directory only after checks
pass; it never replaces an existing destination. Allow free space for compressed
parts plus uncompressed files. No automatic cleanup is performed.

## Capture and publish

The owner of the active engine work freezes the existing workspace and waits
for its build process to exit before capture. These commands do not build an
engine or change the source receipt:

```sh
mkdir -p /absolute/new-assets
python3 scripts/engine-artifacts.py create-workspace \
  --workspace /absolute/existing-workspace \
  --output /absolute/new-assets --name engine-workspace
python3 scripts/engine-artifacts.py create-package \
  --package-dir /absolute/completed-development-package \
  --output /absolute/new-assets --name engine-package
```

Capture streams gzip directly into parts capped at 2,000,000,000 bytes; there is
no full intermediate engine copy or unsplit archive. It writes
`<name>.manifest.json`, `<name>.inventory.jsonl` and numbered parts. Upload all
files to a new private release and commit the pin below using the actual
manifest hashes and metadata hashes printed by the commands. Never replace an
earlier release's assets.

```json
{
  "schema_version": 1,
  "target": "mac-arm64",
  "repository": "etsenake/parc",
  "release": "engine-snapshot-YYYY-MM-DD",
  "source_revision": "MATCHING_PARC_COMMIT_WITH_RESTORE_TOOLS",
  "artifacts": {
    "workspace": {
      "manifest": "engine-workspace.manifest.json",
      "manifest_sha256": "SHA256_OF_MANIFEST",
      "metadata_sha256": "SHA256_REPORTED_BY_CREATE_WORKSPACE"
    },
    "package": {
      "manifest": "engine-package.manifest.json",
      "manifest_sha256": "SHA256_OF_MANIFEST",
      "metadata_sha256": "SHA256_REPORTED_BY_CREATE_PACKAGE"
    }
  }
}
```

The manifest binds every part and the JSONL file inventory by size and SHA-256.
The inventory binds file contents, modes, exact nanosecond modification times
and symlink targets. Extraction rejects unsafe paths, duplicate entries,
special devices and escaping links. Hardlinks become separate files;
ownership, ACLs and extended attributes are not transported. The original
workspace's completed/unfinished state and the completed package's provenance
remain distinct. Transport checks establish artifact integrity, not browser
runtime or feature parity.
