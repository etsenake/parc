# Production release command

```sh
bash scripts/release.sh --type minor
# Other release types: --type patch or --type major
```

Run from clean main on an Apple Silicon Mac. This command is **release-only**:
engine/app build, production signing, notarization, GitHub assets and Homebrew
cask publication. It never installs/replaces/quits/opens Parc, runs startup or
browser tests, or invokes Homebrew install/upgrade/reinstall. Josh runs
`brew upgrade --cask parc` himself. There is no quiet-window timer.
The earlier one-night wait was coordination, not a feature of this command.

A minor release after 1.0.0 is 1.1.0; the Apple bundle build increases
independently. Rerun the same command after interruption. It resumes the saved
version and frozen inputs instead of bumping twice. Asking for a different
release type while a run is stopped and its tag was never published marks that
run abandoned (its run directory, source archive and engine objects are kept),
releases its lease and starts the new release from the current version. A
running run or a published tag still refuses.

## Pipeline

1. Check GitHub login, Xcode/license, Developer ID Application identity for Team
   `94HKA7L2DR`, Homebrew tooling and the `parc-notary` profile. No ad-hoc fallback.
2. Fast-forward clean main, commit and immediately push the version, then extract
   verified Git inputs into ignored build storage. This is an immutable input
   archive, not another Git checkout/worktree. Later commits cannot retarget the
   engine or package. Local edits cause a clear refusal and are never reset,
   stashed, cleaned or overwritten.
3. Find `PARC_ENGINE_WORKSPACE`, `work/engine` or `~/ParcBuild/engine`; use the
   current reviewed cumulative overlay, not every intermediate overlay. Fetch
   before overlay/build operations. Reuse a compatible sealed official ARM64
   non-component engine. Otherwise generate and compile incrementally, preserving
   objects/caches. Build-flag lock changes use verified reconfiguration with the
   exact prior lock; upstream changes get a separate versioned workspace.
4. Seal, build the optimized app, timestamp-sign app/helpers, notarize/staple the
   app, create/sign/notarize/staple the DMG, and publish ZIP/DMG through
   `package-app.sh`. Verify actual release/tag, pristine signatures, stable Team
   and requirement, signed-image hashes, source/overlay identity and Apple
   acceptance. Existing version tags and uploaded bytes are immutable.
5. Download/verify the published ZIP and DMG, including the mounted app's actual
   signatures and ticket. Promote stable/latest and update/push the cask's
   version, URL and checksum in `~/homebrew-tap`. Refresh the local tap metadata,
   check Ruby syntax and audit the cask. **Updating the tap does not install or
   upgrade the app.** Runtime acceptance is neither required nor claimed by this
   artifact-only release path. Separate manual startup tools remain optional.

On a fresh Mac, restore the [saved engine workspace](engine-artifacts.md)
first to avoid a full pinned source sync/build. An unowned existing workspace is
preserved and refused rather than adopted or discarded.

## Logs and recovery

All releases append stage messages and command output to the same file:
`build/master-release-development/nightly-release.log`. Follow it with
`tail -f build/master-release-development/nightly-release.log`; it includes
engine generation/compilation, packaging, signing, notarization and publication.
No shell redirection is needed, and a new run never truncates the log.

`build/releases/current.json` identifies the active run/stage/version/source and
command PID. Each `build/releases/<run>/` contains atomic `state.json`, an
`events.jsonl` stage journal and individual command logs. Swift/compiler detail
is in `package/package-output.log`. Final publication metadata is in
`delivery.json` and `build/releases/latest.json`; it records that no app was
installed/launched and no runtime acceptance is claimed. The deleted recurring
refresh automation is not recreated and its installed-app state is not rewritten.

A nonblocking local lock serializes release/legacy refresh operations. An atomic
temporary GitHub tag lease, `parc-release-in-progress`, prevents two Macs
releasing concurrently. An interrupted run keeps its lease for resumption on the
original Mac. Never steal a live lease. If the original Mac/storage is permanently
lost, an operator must establish it is stopped before removing only that temporary
lease; this command cannot prove a remote machine is dead.

Returned network failures retry unchanged inputs. Pending Apple submissions
resume their stored IDs rather than uploading again. An ambiguous upload with no
confirmed ID stops for reconciliation instead of duplicating it. Interrupted
GitHub uploads compare existing SHA-256 digests and upload only missing assets.

For a cancelled shipping operation, the script requires the original owned
process group to be gone, acquires the engine operation lock, verifies exact
source/overlay/fingerprint/GN arguments, preserves the original receipt, and
converts only the cancelled operation into a resumable failure. GN/Ninja must
then actually succeed before sealing. Completed objects and caches are retained;
a recovery never fabricates a built receipt. Completed source and engine stages
are reused when app packaging resumes. Tooling corrections are committed on
canonical main and the same command is rerun; no manual receipt edits or cache
cleanup are needed.

If compilation exposes a source bug, fix, check and publish the source on main,
then run `bash scripts/release.sh --type minor --refresh-source` (using the saved
release type). This explicitly freezes a new published source archive for the
same version and retains the failed archive, source history and compiled objects.
It is restricted to a stopped engine stage before sealing or packaging; existing
version tags remain immutable. Ordinary resumes keep their original frozen inputs.
Use `--source-commit <full-published-SHA>` with `--refresh-source` to pin the
checked correction when other contributors publish during its checks. The SHA
must be on main, descend from the failed release source and keep its saved
version. Later commits remain available for the next release.

If the release owner died during the read-only overlay check, source refresh
verifies that both the saved command PID and its process group are gone, records
the interrupted check and reruns it against the refreshed archive. It does not
record a successful exit or clear an interrupted apply/build operation.

The command cannot repair arbitrary source bugs, revoke/reissue certificates,
bypass protected authorization, resolve someone else's local edits, or invent
successful checks. It stops with exact logs and preserves previous artifacts for
those conditions. One-time prerequisites are described below.

## Credentials on another Mac

GitHub CLI login, full Xcode/license, Homebrew, available disk space and an
unlocked normal login Keychain are prerequisites. Signing private keys do not
automatically follow an Apple ID login. The selected identity can be backed up to an unlocked 1Password vault:

```sh
python3 scripts/signing-backup.py backup
```

The helper exports only the selected identity as password-encrypted PKCS#12,
generates a strong password in memory, and stores both as concealed fields via
1Password's standard input. No secret enters argv, logs, plaintext files or Git.
It verifies a fresh vault read before reporting success and preserves an existing
backup. Set `PARC_SIGNING_VAULT` if the account has no default vault. Normal
Keychain export approval may be required. The current CLI is not signed in, so
**the actual secure backup remains pending `op signin`/vault unlock**.

On another Mac with that vault available, the release command automatically
restores a missing identity into the normal login Keychain; explicit recovery is
`python3 scripts/signing-backup.py restore`. You can also transfer just this
identity manually using Keychain Access and encrypted PKCS#12. The command selects the sole matching Team Developer ID if
`~/.config/parc/signing-identity` does not yet exist; multiple identities require
one-time `scripts/setup-signing.sh` selection. Never commit private keys or
passwords, put passwords in command arguments, export all identities, or fall
back to ad-hoc signing.

Notary profiles support iCloud synchronization when explicitly provisioned:

```sh
xcrun notarytool store-credentials parc-notary \
  --apple-id '<Apple ID>' --team-id 94HKA7L2DR --sync
```

Enter the app-specific password at the secure prompt. `--sync` cannot combine
with `--keychain`; normal iCloud Keychain availability still applies. The current
Mac's existing working profile was stored without `--sync`; synchronization or
an encrypted private-key backup must not be claimed until actually provisioned.
The script checks credentials before starting compilation. One-time provisioning
or a locked Keychain can require the user's normal OS approval; those cannot
be made unattended by a release script.
