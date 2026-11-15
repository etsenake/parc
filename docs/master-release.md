# Production release command

```sh
bash scripts/release.sh
# Override the bump only when the commits can't choose it: --type patch, minor or major
```

Run from main with no uncommitted changes to tracked files on an Apple Silicon
Mac. This command is **release-only**: engine/app build, production signing,
notarization, GitHub assets and Homebrew cask publication. It never
installs/replaces/quits/opens Parc, runs startup or browser tests, or installs,
upgrades or reinstalls Parc with Homebrew. Users run `brew upgrade --cask parc`
themselves. There is no quiet-window timer.

`release.sh` first loads Homebrew's environment from `/opt/homebrew` when
`brew` isn't on `PATH`, as in a non-login shell. It starts the release with Python 3.12 or later: `python3` when it is
new enough, otherwise a Homebrew `python3.x` (macOS's own Python 3.9 is too
old). Release steps that call `python3`, such as packaging, get that same
interpreter. With no suitable Python it stops and names
`brew install python@3.13`.

## Versions and release notes

Every commit message is one Conventional Commit line (see `AGENTS.md`). The
release reads the commits since the newest published `v*` tag on main, ignoring
merges and subjects that don't parse; git's own `Revert "…"` cancels the change
it reverts and `Reapply "…"` (`Revert "Revert "…""` from git before 2.43)
restores it. A breaking change (`type!:`) makes a major release, any `feat` a
minor one and any `fix` or `perf` a patch. With none of those the command prints
`Nothing to release since vX` and exits successfully before taking the release
lease, committing or building. `--type` overrides the bump when the commits
can't describe it.

A minor release after 1.0.0 is 1.1.0; the Apple bundle build increases
independently. The version commit, `chore(release): X`, holds
`app-version.json`, `release-notes.json` and the generated `CHANGELOG.md`.
`release-notes.json` is the source of truth: newest release first, only feat,
fix, perf and breaking changes, and the UTC date the version was prepared. It
keeps each summary as written; the CHANGELOG, GitHub text and What's New page
capitalize an all-lowercase first word. Both GitHub releases, on etsenake/parc
and etsenake/parc-releases, are titled with the bare version (`1.9.0`) and
their text is only those notes under Heads up, New, Fixed and Faster, rendered
by `scripts/release_notes.py`. A release with none, possible only with a forced
`--type`, says "Small fixes and improvements." there, on the What's New page and
in the appcast. Build provenance stays in `package-report.json`, `delivery.json`
and the run state, never the release text; promotion rewrites the
etsenake/parc release's title and text from the frozen `release-notes.json`, so a resumed
candidate packaged with older text is corrected. If main moves while the
version commit is being pushed, the release merges it and adds those commits to
its notes. A feat or breaking change among them raises the version, since it
isn't published yet; a version chosen with `--type` stays.

Rerun the same command after interruption. It resumes the saved type, version,
notes and frozen inputs instead of bumping twice, and never records a release
twice. A run without `--type` always resumes a stopped run. Asking for a
different `--type` while a run is stopped and its tag was never published marks
that run abandoned (its run directory, source archive and engine objects are
kept), releases its lease and starts the new release from the current version;
the new release's notes replace the abandoned version's. A running run or a
published tag still refuses.

## Pipeline

1. Check Homebrew, GitHub login, Xcode/license, Apple's Metal toolchain,
   Developer ID Application identity for Team `94HKA7L2DR`, Sparkle's key and
   the `parc-notary` profile. No ad-hoc fallback. The preflight provisions what
   it safely can: it installs a missing GitHub CLI with Homebrew, downloads a
   missing Metal toolchain, completes the identity's certificate chain and
   restores missing credentials from 1Password, installing the 1Password CLI
   first (see [credentials](#credentials-on-another-mac)). It stops and names
   the next step for what needs a person: installing Homebrew, `gh auth login`,
   Xcode selection and first-launch setup (both need `sudo`) or unlocking
   1Password. Keychain approval stays macOS's own prompt.
2. Fast-forward main, commit and immediately push the version, then extract
   verified Git inputs into ignored build storage. This is an immutable input
   archive, not another Git checkout/worktree. Later commits cannot retarget the
   engine or package. Uncommitted changes to tracked files cause a clear refusal
   and are never reset, stashed, cleaned or overwritten. Untracked files don't
   block the release and are left where they are, since the inputs come only
   from Git objects.
3. Use `PARC_ENGINE_WORKSPACE` when set. Otherwise choose the first registered
   workspace at `work/engine` or `~/ParcBuild/engine`, falling back to
   `work/engine` if neither is registered. Use the current reviewed cumulative
   overlay, not every intermediate overlay. Fetch
   before overlay/build operations. Reuse a compatible sealed official ARM64
   non-component engine. Otherwise generate and compile incrementally, preserving
   objects/caches. Before reapplying the overlay, `reset-source` overwrites any
   hand edits to Chromium's files and deletes files added by hand (a clean
   workspace is left untouched, so
   nothing extra recompiles). Build-flag lock changes use verified reconfiguration with the
   exact prior lock. A Chromium or depot_tools pin change moves the same
   workspace in place with `retarget --previous-lock`, fetching only the new
   revisions and keeping compiled objects at the same path, so Siso rebuilds
   only what changed, including build settings changed in the same lock; an
   interrupted move resumes toward the same lock. Only another repository
   origin, target platform or lock schema gets a separate versioned workspace
   and a fresh sync.
4. Seal, build the optimized app, timestamp-sign app/helpers, notarize/staple the
   app, create/sign/notarize/staple the DMG, and publish ZIP/DMG through
   `package-app.sh`. Verify actual release/tag, pristine signatures, stable Team
   and requirement, signed-image hashes, source/overlay identity and Apple
   acceptance. Existing version tags and uploaded bytes are immutable.
5. Sign the notarized ZIP with Sparkle's `sign_update` (Keychain account `parc`,
   after checking that key's public half is the app's `SUPublicEDKey`), verify
   the signature with `sign_update --verify`, and write the run's one-item
   `appcast.xml` (`scripts/appcast.py`): build, version, minimum macOS, the
   public ZIP URL, its length and signature, and this version's release notes as
   HTML from the frozen `release-notes.json`.
6. Download/verify the published ZIP and DMG, including the mounted app's actual
   signatures and ticket. Mirror the DMG, ZIP and `appcast.xml` together to the
   public `etsenake/parc-releases` release and make it latest, so Sparkle's feed
   `releases/latest/download/appcast.xml` offers it. Promote stable/latest and
   update/push the cask's version, URL and checksum in `~/homebrew-tap`; the cask
   says `auto_updates true`, so `brew upgrade` leaves Sparkle-updated installs
   alone. Refresh the local tap metadata, trust the tap (Homebrew 7 loads no
   untrusted tap's casks), check Ruby syntax and audit the cask.

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
`delivery.json` and `build/releases/latest.json`, including source, engine,
package, signing, notarization, update-feed and tap identities.

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
The appcast's pubDate is saved in the run state and Ed25519 signatures are
deterministic, so a rerun of the appcast stage writes identical bytes and the
public upload skips the identical asset. A completed appcast that changed on disk
stops the run instead of being signed again. Before the release is marked
complete, `finish` checks that the public latest release serves this appcast's
digest.

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
then run `bash scripts/release.sh --refresh-source`, which keeps the saved
release type. This explicitly freezes a new published source archive for the
same version and retains the failed archive, source history and compiled objects.
It is restricted to a stopped engine stage before sealing or packaging; existing
version tags remain immutable. Ordinary resumes keep their original frozen inputs.
Use `--source-commit <full-published-SHA>` with `--refresh-source` to pin the
checked correction when other contributors publish during its checks. The SHA
must be on main, descend from the failed release source and keep its saved
version. Later commits remain available for the next release.

Fixes frozen in by a refresh join the release's notes. When they change them,
the refresh publishes `chore(release): X notes` on top of the frozen commit,
merged into main if main has moved past it, and freezes that commit instead, so
the GitHub text, the What's New page and main's `release-notes.json` agree. If
it stops before finishing, any resume finishes it, reusing a notes commit it
already published. The version is already
published, so a refresh that would add a feat or breaking change to a version
the commits chose stops; pin an earlier commit or release the higher version
with `--type`.

The merge of commits that landed before the push is written with Git plumbing
and never touches the checkout, so a kill at any point in it leaves main clean
on the version commit, and a rerun builds the merge again. The checkout stays on
the version commit; the next release fast-forwards it. A release never starts
from local commits main lacks, and a version commit carrying anything besides the
version files that main lacks, as after main is rewritten, stops for
reconciliation instead of being merged away.

If the release owner died during overlay validation, or during a Git
command or a preflight step (`gh`, `xcrun`, `xcodebuild`, `security`, a Homebrew
install of a missing tool, or the signing-key restore), for example while a
source refresh was fetching, source
refresh verifies that both the saved command PID and its process group are gone,
records the interrupted command and reruns from its start. A live PID or group
still refuses. It does not record a successful exit or clear an interrupted
overlay apply. A cancelled shipping build is handed to the cancelled-build
recovery instead: once its process group is gone, the refresh freezes the new
source and the engine stage verifies the old receipt with replaced inputs before
compiling incrementally, so stopping a compile and refreshing needs no plain
resume first.

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
backup. Set `PARC_SIGNING_VAULT` if the account has no default vault, and
`OP_ACCOUNT` to use a 1Password account other than the default `my.1password.ca`. Backup is interactive and may unlock through the 1Password app. Normal
Keychain export approval may be required. A successful verified helper result is required before relying on a vault
backup; this guide is not a current backup receipt.

On another Mac with that vault available, the release command automatically
restores a missing identity into the normal login Keychain, installing the
1Password CLI (`brew install --cask 1password-cli`) first when `op` is missing;
explicit recovery is `python3 scripts/signing-backup.py restore`.

An identity is only valid for code signing when the Apple intermediate that
issued its certificate, "Developer ID Certification Authority" (G2 for current
certificates), is in a keychain. Without it `security find-identity` lists the
identity but counts none valid. When a Team identity is present but not valid,
`restore` and the release preflight read its issuer, download that intermediate
from Apple's certificate authority page over HTTPS, check with `openssl verify`
that the Apple Root CA in the system roots issued it, import it into the login
Keychain and check the identity again. A certificate from any other issuer, or
one that fails the check, is never imported. An identity that is still invalid
afterwards, for example because it expired, stops the release. You can also transfer just this
identity manually using Keychain Access and encrypted PKCS#12. The command selects the sole matching Team Developer ID if
`~/.config/parc/signing-identity` does not yet exist; multiple identities require
one-time `scripts/setup-signing.sh` selection. Never commit private keys or
passwords, put passwords in command arguments, export all identities, or fall
back to ad-hoc signing.

The notarytool profile `parc-notary` (`PARC_NOTARY_PROFILE` selects another) is
created once with Apple's secure prompt for the app-specific password:

```sh
xcrun notarytool store-credentials parc-notary \
  --apple-id '<Apple ID>' --team-id 94HKA7L2DR
```

notarytool keeps the profile in the data-protection Keychain under its own
access group, `com.apple.gke.notary`. No other process can read it back, even
with Keychain approval: an attributes-only query from an ordinary process gets
`errSecMissingEntitlement`. So `signing-backup.py backup` must run in a
terminal. It asks for the profile's Apple ID and, at a no-echo prompt, the
app-specific password. It checks them with `notarytool history` before saving
anything, then saves the 1Password item "Parc notary profile" (Apple ID, Team ID
and the concealed password), verified by a fresh vault read. An existing item is
checked with Apple again and preserved either way. Use the profile's existing
app-specific password; if it is lost, create a new one at appleid.apple.com.
`restore` leaves a profile that passes `notarytool history` alone. Otherwise it
recreates the profile with `notarytool store-credentials`, which checks the
password with Apple before saving, then checks it again. notarytool only takes
the password in argv or at its `getpass` prompt, and with no controlling
terminal that prompt reads standard input, so both commands run in a new session
and receive the password on stdin. The release preflight runs `restore` when the
profile fails, installing the 1Password CLI first when it is missing, rechecks
the profile, and stops if it still fails.
`store-credentials --sync` remains Apple's separate iCloud Keychain route; it
cannot combine with `--keychain`. The script checks credentials before starting
compilation. One-time provisioning or a locked Keychain can require the user's
normal OS approval; those cannot be made unattended by a release script. Confirm the verified backup receipt before treating these credentials as
recoverable on another Mac.

The Sparkle EdDSA private key lives in the release Mac's login Keychain, under
Sparkle's service `https://sparkle-project.org` with account `parc`. If it is
lost, installed Parcs reject every later update. `signing-backup.py backup` also
saves it as the 1Password item "Parc Sparkle EdDSA key" (account, public key and
the concealed private key), after checking that the Keychain key's public half
is Parc's `SUPublicEDKey`. Sparkle's `generate_keys --account parc -x` exports it
into a 0600 file in a private temporary folder that is removed straight away,
and the item is verified by a fresh vault read. `restore` imports a missing key
the same way with `generate_keys -f` and checks the public key afterwards,
removing an imported key that doesn't match; it leaves a present key and
identity alone. Two vault items with the same title stop both commands. The release preflight runs `restore`
when either credential is missing, installing the 1Password CLI first when it
is missing, and stops if the Sparkle key is still missing. As with the identity, confirm the verified backup exists before relying on it. Never run plain `generate_keys
--account parc` on a Mac without the key: it would create a new key that no
installed Parc trusts, and the appcast stage refuses to sign with it. The first
signing asks for Keychain access to `sign_update`; choose Always Allow so later
releases run unattended.
