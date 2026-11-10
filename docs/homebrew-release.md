# Versioned Parc releases and Homebrew

Use [the release command](master-release.md) for production:

```sh
bash scripts/release.sh
```

Version comes from Conventional Commits; `--type major|minor|patch` overrides the
calculation. The command builds, signs, notarizes/staples, publishes GitHub assets
and publishes/verifies the Homebrew cask. It never installs, quits or launches
Parc, performs browser/startup checks, waits for quiet main, or runs a Homebrew
install/upgrade/reinstall. Users upgrade manually.

## Package a versioned candidate

`scripts/package-app.sh` is the supported focused packaging entry point for an
already sealed compatible engine. `--stable` creates an immutable versioned
candidate; normal production orchestration completes publication through the
master command. Packaging verifies release optimization, standalone engine
inputs, timestamped Developer ID signing, Apple acceptance and stapling. The
signed/notarized DMG contains Parc and an Applications shortcut; its mounted app
must match every signed-image hash. The ZIP preserves the package report.

```sh
bash scripts/package-app.sh --stable /absolute/sealed/engine-artifacts.json
```

Explicit release reuse still checks the source lock, overlay, shipping flags,
framework signatures and image hashes. `--from-release` refuses any `Engine/`
difference; a documentation-only difference can instead use a compatible local
sealed manifest after the normal checks. It does not authorize a fresh engine
sync/build. Keep active source and packaging inputs frozen and preserve compiled
objects/caches.

Notarization logs remain next to the package in `notarization/` and
`dmg-notarization/`. Resume the same frozen operation after interrupted status or
staple checks. An upload without a confirmed submission ID requires reconciliation
with notarization history before another submission. Never overwrite published
assets, retag a release or recompile merely to resolve a pending job. Secrets
remain in the normal local Keychain.

## Publish the tap from verified notarized artifacts

The master calls `scripts/publish-homebrew.py` with `--artifact-only --resume`
and the run's signed `--appcast`. This validates published ZIP/DMG hashes,
tag/source/version, package report, mounted-app signatures and Apple ticket,
then promotes the stable release and publishes the cask.

The appcast comes from `scripts/appcast.py`, offers the exact public ZIP and is
mirrored with the ZIP and DMG into `etsenake/parc-releases`. Existing differing
asset bytes are never overwritten. The source repository can stay private while
the cask and Sparkle download public release artifacts without a GitHub login.

The tap checkout is `~/homebrew-tap`; the installed Homebrew tap is a separate
clone. Preserve edits in both. Publication verifies the cask's version/hash,
Ruby and download strategy, then commits/pushes and compares remote state. See
[master release](master-release.md) for recovery and stage receipts rather than
maintaining a second release checklist here.

## Optional historical receipts

Production releases and completed fixes do not wait for user confirmation. The
optional `record-release-acceptance.py --user-confirmed` mode binds a dated exact statement
to the immutable source/version and raw package-report hash, verifies the artifact,
and preserves any interrupted raw observation unchanged.

Historical acceptance-backed publication remains a separate tool capability.
This guide does not authorize installation, launch, browser tests, profile access
or automatic rollback. Current permissions are in [AGENTS.md](../AGENTS.md).
