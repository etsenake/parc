# Versioned Parc releases and Homebrew

Josh explicitly confirmed normal startup of **1.0.0**. The earlier uncontrolled
observer was interrupted by his deliberate test of a specific behavior; keep
its raw result unchanged and do not present it as an automated pass. The
separate behavior bug does not block the confirmed production release.
The existing tag/assets are immutable and its stable/latest DMG distribution
is authorized. Current installed-app operations belong to the other agent:
do not launch, replace, downgrade or rebuild it. Actual Homebrew DMG
installation/upgrade validation remains pending an authorized app operation.

The next source release is **1.0.1, bundle build 2**. Leave `app-version.json`
unchanged until Josh supplies the ready source. At that point:

```sh
python3 scripts/app_version.py bump 1.0.1
```

Review and check the complete source, commit and immediately push it to main,
then verify the local/remote SHA. Root must hand off the shared build lock
before packaging. Keep that fetched source snapshot and all packaging inputs
frozen through publication and installation. Never discard engine objects or
caches to resolve a packaging or documentation difference.

## Package a versioned candidate

Use `scripts/package-app.sh`; it requires release optimization, a verified
standalone engine, timestamped Developer ID signing for Team `94HKA7L2DR`, Apple
acceptance, stapling and Gatekeeper verification. It creates a signed DMG with
Parc and an Applications shortcut, notarizes and staples the DMG separately,
and verifies the mounted app against every signed-image hash. A ZIP retains
the package report and the engine-reuse layout.

```sh
bash scripts/package-app.sh --stable /absolute/sealed/engine-artifacts.json
# A compatible promoted release can also supply its engine:
bash scripts/package-app.sh --stable --from-release v1.0.1
```

`--stable` publishes an immutable **versioned pre-release candidate**, not
latest. A passed automated receipt or separately recorded explicit user
confirmation permits promotion. Preview cleanup does not delete `v<version>` releases. Automatic engine
reuse selects promoted versioned releases or ordinary `app-*` previews; it
excludes unaccepted versioned candidates. Explicit release reuse still checks
the source lock, engine overlay, shipping flags, framework signatures and image
hashes.

`--from-release` intentionally refuses any `Engine/` difference. When only
`Engine/README.md` or other documentation differs, pass the compatible local
sealed manifest directly instead. The normal seal/overlay/source-lock/flags
checks still apply. A documentation difference does not authorize a fresh
Chromium sync or rebuild. For this Mac the retained 327 seal is
`build/engine-327-production-20261106T025713Z/engine-artifacts.json`; use it only
if those checks accept the ready source. A real engine-input change requires
the engine owner's new compatible seal.

Notarization receipts/logs stay beside the package in `notarization/` and
`dmg-notarization/`. Resume the same frozen operation after an interrupted
status/staple check:

```sh
python3 scripts/notarize-app.py /absolute/run/development \
  --profile parc-notary --team 94HKA7L2DR
python3 scripts/package-dmg.py /absolute/run/development \
  --output /absolute/run/Parc-1.0.1-arm64.dmg \
  --sign-identity <same-Developer-ID-SHA1> --profile parc-notary --team 94HKA7L2DR
```

An upload without a confirmed submission ID requires reconciliation with
`notarytool history`; never submit a second copy automatically. Read Apple's
log even after acceptance. Keep passwords and private keys in the normal local
Keychain. Do not retag, overwrite assets or recompile to resolve a pending job.

## Install immediately, then record startup

Install and open each completed published candidate before tap metadata,
documentation or newer-main work. Quit the current Parc normally first. Stage
a fresh bundle and preserve the old one; never merge bundles or alter the
profile. These are future-candidate commands, to run only after Josh's signal:

```sh
set -e
PARC_PACKAGE=/absolute/run/development
PARC_TAG=v1.0.1
PARC_COMMIT=$(gh release view "$PARC_TAG" -R etsenake/parc --json targetCommitish --jq .targetCommitish)
PARC_RECEIPTS=$(mktemp -d "$PWD/build/release-acceptance.XXXXXX")
PARC_STAGE=$(mktemp -d /Applications/.Parc-install.XXXXXX)
codesign --verify --deep --strict "$PARC_PACKAGE/Parc.app"
ditto "$PARC_PACKAGE/Parc.app" "$PARC_STAGE/Parc.app"
codesign --verify --deep --strict "$PARC_STAGE/Parc.app"
if [ -d /Applications/Parc.app ]; then
  mv /Applications/Parc.app "$PARC_RECEIPTS/previous-Parc.app"
fi
mv "$PARC_STAGE/Parc.app" /Applications/Parc.app
rmdir "$PARC_STAGE"
python3 scripts/record-release-acceptance.py \
  --package "$PARC_PACKAGE" --tag "$PARC_TAG" --commit "$PARC_COMMIT" \
  --output "$PARC_RECEIPTS/acceptance.json"
```

The source-owned recorder refuses an already-running app. It verifies the
installed identity/version, every packaged signed-image hash, production Team
and stable designated requirement, strict signature, ticket and Gatekeeper
before normal `open`. It observes that exact process for 90 seconds (minimum
60), rejects exits/restarts and new Parc crash reports, then checks code hashes,
identity and normal deep signing again. The post-launch check preserves normal
custom Finder icon metadata. It resamples crashes after final signature/PID
verification so a late helper report cannot pass.

The receipt binds the actual release tag/commit, app version/build and SHA-256
of the exact raw `package-report.json` shipped in the ZIP. This establishes
bounded startup acceptance, not browser functionality or encrypted-restart
acceptance. Leave any normal protected authorization to Josh; do not inspect or
bypass it, and do not retrieve Keychain secrets.

On failure, stop and preserve the candidate, previous bundle, receipt and logs.
Do not automatically downgrade, relaunch, rebuild, replace assets or promote
the cask. Josh controls the next action. Remove rollback/obsolete bundles only
after the passed receipt and final integrity check.

## Explicit user confirmation

An interrupted automatic observation does not override Josh's explicit account
of what he tested. When he confirms normal startup of the exact release, record
that statement, its date and the immutable source/version/report binding using
the separate mode. Do not reuse a confirmation for another candidate.

```sh
python3 scripts/record-release-acceptance.py --user-confirmed \
  --package "$PARC_PACKAGE" --tag "$PARC_TAG" --commit "$PARC_COMMIT" \
  --statement-file /absolute/exact-user-statement.txt \
  --confirmed-at "$PARC_CONFIRMED_AT" \
  --raw-observation /absolute/original-observation.json \
  --output "$PARC_RECEIPTS/acceptance-user-confirmed.json"
```

Set `PARC_CONFIRMED_AT` to the actual confirmation's ISO 8601 timestamp with
timezone. This mode verifies the preserved **package artifact**, all signed
images, production Team/requirement, strict signing, ticket and Gatekeeper; it
does not inspect current app processes, launch an app, replace anything or
access its profile/Keychain. Its receipt explicitly says `user-confirmed` and
`automatic_startup_acceptance_claimed: false`. The original observation bytes,
hash and parsed result are retained without changing `passed` or its duration.
The 1.0.0 receipt uses Josh's November 5 confirmation of normal startup.

## Promote and publish the tap

After either valid acceptance route, the publisher verifies the ZIP/DMG GitHub digests,
exact tag object/commit, archived report hash/version and receipt, production
identity and Apple acceptance before promoting stable/latest and writing the
cask. Automatic evidence must pass the full duration/no-crash gate; explicit
user evidence must include the dated statement and independent artifact
verification. Both routes require the exact commit, raw report hash and version.

```sh
python3 scripts/publish-homebrew.py "$PARC_TAG" \
  --acceptance "$PARC_RECEIPTS/acceptance.json" --tap "$HOME/homebrew-tap"
```

Review the tap diff and parse its Ruby, selectively commit and immediately push
the cask change from `~/homebrew-tap`, and compare local/remote main SHA. The
installed tap is a separate clone at `$(brew --repo etsenake/tap)`; preserve its
edits and fast-forward it to the published main before these checks:

```sh
brew ruby -- -c "$HOME/homebrew-tap/Casks/parc.rb"
brew ruby "$HOME/homebrew-tap/test/parc_download_strategy_test.rb"
brew audit --cask etsenake/tap/parc
brew fetch --cask etsenake/tap/parc
brew upgrade --cask etsenake/tap/parc
```

Homebrew may replace the same manually installed candidate while registering
the actual upgrade. Keep a rollback copy, then run the recorder again with a
new receipt path before removing it. Verify the installed Homebrew version and
all code hashes. Do not change the chosen default browser or the Parc profile.
The public tap contains metadata only; private assets authenticate through the
user's GitHub login without tokens in cask metadata or URLs.
