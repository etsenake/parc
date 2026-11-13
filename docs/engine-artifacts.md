# Existing engine snapshots

## Engine on an external drive

The primary way to share one engine between Macs is an external APFS drive
(a Thunderbolt or USB4 NVMe drive) carried between them. Siso trusts an engine
only at the absolute path where it was built, so the drive is mounted at the
engine's existing folder (where the checkout's `work/engine` link points),
not under `/Volumes`; the same path on every Mac keeps every Siso record valid.

`python3 scripts/engine_drive.py prepare --volume NAME` sets a Mac up with the
drive plugged in. It refuses a non-APFS or internal disk, a drive holding other
files, and an engine whose operation lock is held. On the first Mac it copies
the engine onto the empty drive with `ditto`, keeping every file date; on a
later Mac it finds the drive's engine and copies nothing. It then moves the
Mac's own engine folder aside to `<folder>.local-<time>` (delete it once the
drive works), creates the empty mount folder, adds
`UUID=<volume> <folder> apfs rw` to `/etc/fstab` with administrator rights once
so the drive always mounts there, and remounts it there now. It writes
`.metadata_never_index` so Spotlight leaves the drive alone; macOS ignores
ownership on it, so different user names on the Macs don't matter. `status`
reports whether the engine folder is the drive and has its mount setting;
`eject` refuses while an engine operation runs and otherwise ejects the drive.
Releases then build on the drive through the engine link as usual. Matching
Xcode file dates is still needed while the SDK comes from Xcode; the engine's
own SDK copy (see [Engine](../Engine/README.md#build-configuration)) removes
that need after its one-time rebuild.

With a drive in use, configure the NAS below with `setup --mode backup`: every
release still packs its engine into the NAS snapshot in the background, but it
never takes an engine from the NAS and finishes without waiting for the upload,
recording "backing up to the NAS in the background" instead; `status` shows the
snapshot's time afterwards. Restoring that backup (for a replacement drive or a
Mac without the drive) is a manual `workspace --from snapshot`, which unpacks
at the engine folder.

## Shared engine storage on a NAS

`scripts/engine_storage.py` lets several Macs share one engine workspace through
an NFS share on a NAS, so a Mac other than the last builder doesn't start from
scratch. It is off unless the Mac has a settings file at
`~/.config/parc/engine-storage.json` (or the path in `PARC_ENGINE_STORAGE`):

```json
{"schema_version": 1, "share": "nfs://nas.local/volume1/parc-engine-nfs"}
```

`setup --share URL` writes that file (keeping other keys) and prepares a new
Mac in one run: it downloads Apple's Metal toolchain when `xcrun metal
--version` fails, mounts the share, creates the current snapshot's build
folder and, on a Mac with no engine workspace anywhere a release looks (the
local workspace, the checkout's `work/engine`, `~/ParcBuild/engine`,
`PARC_ENGINE_WORKSPACE` or the snapshot's build path), matches Xcode's file
dates. It prints what is still needed, such as a permission, and exits non-zero
until nothing is.

Optional keys and defaults: `mount_point` (`/Volumes/parc-engine-nfs`),
`image` (`parc-engine.sparsebundle`), `volume` (`ParcEngine`),
`image_workspace` (`ParcBuild/engine`), `local_workspace` (whatever the
checkout's ignored `work/engine` links to, or that folder itself),
`min_image_mb_per_second` (100), `attach_attempts` (3), `holder_stale_hours`
(48) and `lock_wait_seconds` (600).

Siso keeps its record of finished build steps inside the workspace, keyed by
each file's absolute, symlink-resolved path. Those records travel inside a
snapshot, but they only match when the workspace sits at the same absolute
path where it was last built; anywhere else, nearly every step reruns. A
snapshot's `metadata.json` records that path as `workspace`, so unpacking puts
the workspace back there on every Mac, creating the folder with administrator
rights once when the Mac cannot otherwise write there (non-interactive `sudo`,
a terminal prompt, or a macOS password dialog), and points `work/engine` at it
so the checkout still shows it. A build there then writes records at that same
path, which the next snapshot carries.

Siso also records the timestamps of Xcode's files that the build reads, and two
Macs with the same Xcode release can carry identical files with different
dates. A changed SDK date makes Siso rebuild the system module cache, and
every compile that depends on it follows. Publishing therefore records the
timestamp and content hash of every file in Xcode's macOS platform, default
toolchain and `usr` folder, in the snapshot and as `xcode-files.json.gz` at the
share root. Before unpacking a snapshot, right after creating its folder so
both administrator requests come together, and before building in the disk
image, the tool gives each of this Mac's Xcode files whose contents match the
record its recorded timestamp, asking for administrator rights only when
something needs changing. Files with different contents keep their dates, so a
genuinely different Xcode still rebuilds what depends on it. macOS's App
Management protection refuses changes inside installed apps even to an
administrator, so the app that runs the script (Terminal, T3 Code or another)
needs System Settings > Privacy & Security > App Management turned on once on
each Mac that unpacks or builds a copy from another Mac; a refusal is reported
with that instruction and does not ask for the password again. A failed
alignment does not stop the unpack; it says the build may redo Xcode-dependent
work.
`record-xcode` writes the record for the snapshot already on the share and
`align-xcode` reruns the alignment.

The share holds two copies of the engine. `parc-engine.sparsebundle` is an APFS
disk image holding a live workspace that one Mac at a time opens and builds in.
`snapshots/current` is a packed snapshot of the latest published workspace,
with `pin.json` and `metadata.json` describing it. The NFS export maps all
users to the NAS administrator; the image is attached with ownership ignored,
so its files belong to whoever opens it. It mounts visibly as ParcEngine in
Finder's sidebar; a `.metadata_never_index` file inside the image keeps
Spotlight from indexing it on every Mac. The app or terminal that runs builds
needs macOS's Network Volumes permission once; a first access waits on that
prompt.

`resolve` (JSON) and `workspace` (path only) pick the workspace in this order:

1. The local workspace, when its source lock and overlay already match the
   checkout. No network is used.
2. The disk image, when the share is reachable, a request to the NAS answers
   within `max_image_round_trip_ms` (3), an uncached read reaches the speed
   threshold, the image opens and its workspace is ahead of the local copy.
   Both are measured before opening: opening the image sends the NAS about
   18,000 requests, 7,600 of them lock round trips that run one after another,
   so a wired Mac at under 1 ms opens it in about 10 seconds while Wi-Fi at
   27 ms takes minutes however much bandwidth it has. The round trip is timed
   with lock requests on a per-Mac probe file at the share root.
   A Mac writes `parc-engine.sparsebundle.holder.json` as "opening" before it
   tries and "open" once mounted, and removes it when an attempt fails or the
   image is ejected; `status` shows it, and another Mac reports who holds or is
   opening the image. An "opening" record older than `attach_wait_seconds`
   (600) plus five minutes is ignored as an interrupted attempt. An open that
   outlasts that wait is given two more minutes to finish in the background,
   then ejected if it half-attached; a refusal reports macOS's reason, such as
   a lock held by another Mac or an interrupted open.
3. The NAS snapshot, unpacked with the normal restore tool at its recorded
   build path when it is ahead of the local copy and the disk has room. The
   whole unpack holds the share's snapshot lock and stops if another Mac
   replaced the snapshot after it was chosen. An outdated Parc-owned workspace
   there, or at the previous local path, is moved aside and deleted after a
   successful unpack, or put back if the unpack fails. When space is short it
   is deleted first, but only when every byte of the snapshot checks out and
   the room is certain: macOS's available space for important use (which
   includes space it frees on demand, such as Time Machine local snapshots)
   plus only the storage the older copies on that disk own outright, not
   blocks shared with APFS clones or files with another hard link; a disk that
   can't report that ownership counts nothing. Otherwise nothing is removed. A connection lost mid-unpack after such a deletion leaves no engine
   copy until the next run unpacks again. Folders without a Parc receipt are
   never touched.
4. The local workspace as it is.

A copy built on an earlier Chromium lock from the checkout's own Git history
is a usable starting point that the release then upgrades in place; it ranks
below every copy on the current lock, the most recent earlier lock first, so a
new Mac starts from an older snapshot instead of downloading Chromium. A copy on
a lock outside that history is ignored. Among copies on the current lock,
"ahead" compares by overlay version: the
checkout's exact overlay ranks highest, a copy with a newer overlay than the
checkout is unusable, and the local copy wins ties. A Mac whose engine just
changed therefore compiles locally instead of unpacking an older NAS copy.
Copies at the same version cannot be ordered by build progress. To move an
unfinished build in the disk image, stop it, run `detach` on the first Mac and
build on the second. To move an unfinished local build, stop it and run
`publish --handoff` on the first Mac; an interrupted build stays packable, but
one still running is refused. A handoff always packs, because build progress
doesn't change the engine's identity. The snapshot then carries a handoff mark
that the next other Mac takes automatically, once, even over its own copy at the
same version. A stopped release whose engine stage is unfinished moves with it:
its run folder is copied under the snapshot lock to `handoff/current` on the
share, tied to that snapshot's handoff mark, and the first Mac marks it
`handed-off` so it won't resume there. The next `release.sh` (or `take-handoff`)
on another Mac without its own unfinished release claims it under the lock, so
only one Mac can, refuses if the snapshot no longer carries the matching mark,
unpacks the snapshot, stages a copy of the run with its paths relocated to that
checkout and home, moves it into place only when complete, and resumes it under
the same release lease. A failed takeover removes its local copy and releases
both claims, on the run and on the snapshot, so it can be retried. A release past its engine stage must finish where
it is. `--from image|snapshot|local` forces a copy; a requested copy that is
unavailable is an error rather than a silent fallback.

If the Mac that has the image open loses its connection or cannot eject, pass
`--take-over` on the other Mac once the first no longer has it open. It clears
the first Mac's holder record, opens the image, verifies its file system and
repairs it when needed. Publishing removes uploads that an earlier interrupted
publish left on the share.

A restored workspace must regenerate its build plan; compiled objects are kept.
Unpacking and packing log progress every 30 seconds (gigabytes done, a
percentage and elapsed minutes, then the verification phase), and messages
from the restore and pack tools appear as they happen.
`publish --workspace PATH` packs a workspace into a new snapshot and replaces
`snapshots/current` under a share-wide lock, skipping an unchanged engine.
Without `--workspace` it publishes the latest release's workspace, opening and
ejecting the disk image when that workspace lives there, so a failed upload can
be retried from either Mac. `detach` ejects the image and clears this Mac's
holder record; `status` reports the local, image and snapshot state.

With settings present and `PARC_ENGINE_WORKSPACE` unset, the
[release](master-release.md) resolves its workspace this way and keeps that
choice when resumed. It always runs the checkout's own storage script, the same
version as the release script, even when resuming a release whose frozen
inputs predate a storage change. It runs `resolve --repo CHECKOUT --source FROZEN`: the
checkout's `work/engine` link (or `local_workspace`) names this Mac's
workspace, and the release's frozen inputs supply the engine lock and overlay
it must match, so a Mac whose engine is current reuses it and an unpack's link
lands in the checkout where the next release finds it. Once the engine is sealed, the release starts packing it
into the NAS snapshot in the background, writing to the release log, and
continues packaging alongside it: both only read the sealed engine, so they
share the workspace (see [capture](#capture-and-publish)). Its last stage
waits up to four hours for that upload, ejects an image it opened (stopping
an eject that takes over ten minutes), and adds the upload's outcome to the
release's final line; an upload still running
then keeps going in the background and is reported as such. A resumed release waits only on its own uploader process. A
failed or unstartable upload, unreadable settings or a failed NAS engine choice
is reported (the last falls back to this Mac's workspace) and never stops the
release.
For a development engine build, pass
`--workspace "$(python3 scripts/engine_storage.py workspace)"` to
`scripts/engine-source.py`.

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
completed engine. Capture and restore use the checkout’s `Engine/source-lock.json` for
direct Chromium workspaces. Old published assets remain on GitHub; these tools
restore only the current direct-engine workspace format.
The development package includes `Parc.app`, its sibling
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
remain distinct.
