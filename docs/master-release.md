# Production release command

From clean `main` on an Apple Silicon Mac:

```sh
bash scripts/release.sh --type minor
# Other release types: --type patch or --type major
```

This is the production entry point. It needs no agent to sequence engine work,
packaging, publication, installation or cask updates. A minor release after
1.0.0 is 1.1.0; the bundle build number increases independently. Rerun the same
command to resume an unfinished release without another version bump.

The command checks GitHub login, Xcode/license, the configured Developer ID
Application identity for Team `94HKA7L2DR`, and `parc-notary`. It fast-forwards
clean main, commits and immediately pushes the version, then extracts verified
Git inputs into ignored build storage. This is an immutable build-input archive,
not another Git checkout/worktree. Later commits cannot retarget the release.
All source edits remain visible on canonical main. Local edits are preserved and
cause a clear refusal instead of an automatic stash/reset/clean.

A nonblocking local lock serializes refresh/release/install operations. An
atomic temporary GitHub tag lease, `parc-release-in-progress`, prevents two
Macs releasing simultaneously. It is distinct from immutable version tags.
An interrupted run keeps its lease for resumption on the original Mac. Never
steal a live lease. If that Mac/storage is permanently lost, an operator must
verify it is stopped before removing only that temporary lease; the command
cannot prove a remote machine is dead.

## Stages and recovery

1. Find `PARC_ENGINE_WORKSPACE`, `work/engine`, or `~/ParcBuild/engine`. Apply
   the single current reviewed cumulative overlay after fetching main. Do not
   rebuild each intermediate overlay or renumber manifests automatically.
2. Reuse a compatible completed official non-component ARM64 engine. A real
   input change triggers normal generation and incremental shipping compilation,
   preserving output and caches. Build-flag-only lock changes use verified
   `reconfigure` with the exact previous lock from Git history. An upstream
   dependency change uses a separate versioned workspace, preserving the old one.
   A new machine without a restored workspace performs the pinned source sync;
   restore the [saved engine workspace](engine-artifacts.md) first to avoid it.
3. Seal, build the optimized app, timestamp-sign app/helpers, notarize/staple
   the app, create/sign/notarize/staple the DMG, and publish ZIP/DMG using
   `package-app.sh`. Stable version tags and uploaded bytes are immutable.
   Interrupted uploads reconcile matching digests and upload only missing assets.
4. Immediately stop Parc, make and verify a private profile backup, stage a
   standalone bundle, retain rollback, replace `/Applications/Parc.app`, and open
   it normally. Strict signing, Team/requirement, ticket and every signed-image
   hash are checked before opening. Observe the same process for 90 seconds and
   reject new app/helper crash reports. Post-launch checks preserve the normal
   custom Finder icon metadata. No browser-driving regressions are run.
5. Verify release/acceptance evidence, promote stable/latest, update and push
   `~/homebrew-tap`, refresh the installed tap and audit the cask. **Never run
   `brew upgrade`, `brew install` or `brew reinstall` automatically.** Josh runs
   `brew upgrade --cask etsenake/tap/parc` himself. Updating the tap is publication;
   upgrading the installed Homebrew receipt is a separate user action.
6. Remove this run's superseded rollback app bundles only after acceptance;
   register the installed app. Keep the newest pristine package, profile backups,
   reports, receipts, seals and engine output. Keep `build/` excluded from
   Spotlight Search Privacy so retained artifacts do not appear as extra apps.

Logs and atomic state are under `build/releases/<run>/`; current state is
`build/releases/current.json`. `events.jsonl` records stage transitions,
individual `*.log` files hold command output, and `state.json` records frozen
source/version/overlay, process and stage status. Installation also updates
`build/recurring-prod-refresh/state.json`; this does not recreate the deleted
recurring automation. The release command starts immediately when invoked; it
contains no quiet-window timer. Tonight's one-time wait for other contributors
to finish was a coordination instruction, not release-command behavior.

Network operations retry unchanged inputs. Returned compile failures preserve
objects and rerun incrementally. Apple submission IDs/receipts resume pending
status/stapling without duplicate submissions. An upload without a confirmed
Apple submission ID stops for reconciliation rather than submitting again.
A failed startup stops without automatic downgrade, relaunch or promotion;
failed evidence is never rewritten as passed. A process interrupted before a
completed startup result can receive a fresh recorded observation on resumption.
The command does not repair source bugs, revoke/reissue certificates, bypass
protected authorization, resolve unrelated local edits or invent acceptance.

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
