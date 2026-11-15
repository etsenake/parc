# Existing engine snapshots

## Engine on an external drive

The primary way to share one engine between Macs is an external APFS drive
(a Thunderbolt or USB4 NVMe drive) carried between them. The engine lives at
the drive's own folder under `/Volumes`, such as `/Volumes/Parc`, and builds
there in place. Siso trusts an engine only at the absolute path where it was
built, so use the same drive name on every Mac; macOS gives the drive that same
path as long as no other mounted volume shares its name.

`python3 scripts/engine_drive.py prepare --volume NAME` sets a Mac up with the
drive plugged in and needs no administrator rights. It refuses a non-APFS or
internal disk, a drive holding other files and an engine whose operation lock
is held. On the first Mac it copies the engine the checkout's `work/engine`
link names onto the empty drive with `ditto`, keeping every file date, then
registers the copy at the drive's path with the engine tool's move proof (the
`adopt-clone` checks without its same-volume rule), so the first build there
regenerates and recompiles. Pass `--lock` with the source lock the engine was
built with when the checkout's lock has moved on. On a later Mac it finds the
drive's registered engine and copies nothing.

Either way it points the checkout's `work/engine` link at the drive, where
releases and the engine tools find it, and writes `.metadata_never_index` so
Spotlight leaves the drive alone. The Mac's own engine folder stays untouched
as a fallback; delete it once the drive works. macOS ignores ownership on the
drive, so different user names on the Macs don't matter. `status` reports
whether the linked engine is on an external drive and registered at its path;
`eject` refuses while an engine operation runs and otherwise ejects the drive.
The engine builds with its own Xcode folder on the drive (see
[Engine](../Engine/README.md#build-configuration)), so another Mac builds
incrementally whatever Xcode it has installed.

## Restore the saved artifacts

A release in the maintainer's private archive repository, `etsenake/parc-private`,
stores the **existing incremental workspace** and the **last
completed development package** separately. Restoring the workspace preserves
source repositories, toolchains, object files and Siso build state. Its captured
receipt may describe an unfinished build; the snapshot does not turn it into a
completed engine. Capture and restore use the checkout’s `Engine/source-lock.json` for
direct Chromium workspaces. Old published assets remain on GitHub; these tools
restore only the current direct-engine workspace format.
The development package includes `Parc.app`, its sibling
engine libraries and its original `package-report.json`.

Use Python 3.12 or later and authenticate GitHub CLI with access to
`etsenake/parc-private`. The release and SHA-256 identities are pinned in
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
workspace depth may invalidate generated dependencies;
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
engine or change the source receipt. Workspace capture holds the workspace's
operation lock shared, as packaging does: sealing and packaging can read the
engine during a capture, while a build, overlay change or anything else that
needs the workspace to itself is refused until it ends, and packaging still
refuses a running build. The Git checks of both run with Git's optional index
refresh off, so neither rewrites a file the other is reading:

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
files to a new release in `etsenake/parc-private`, never the public
repository, and commit the pin below using the actual
manifest hashes and metadata hashes printed by the commands. Never replace an
earlier release's assets.

```json
{
  "schema_version": 1,
  "target": "mac-arm64",
  "repository": "etsenake/parc-private",
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
remain distinct.
