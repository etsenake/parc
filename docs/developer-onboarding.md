# Developer onboarding

Complete this checklist on a new machine before feature work. Use the actual
checkout paths. Setup does not claim backlog items or authorize a new build.

1. **Read the contract.** Read [AGENTS.md](../AGENTS.md), [README](../README.md),
   [collaboration](collaboration.md), [product status](parity.md) and
   [development setup](development-setup.md). Check current ownership directly;
   an old task note does not prove someone is active.

2. **Check the checkout.** Verify origin, branch and working tree. Fetch
   `origin/main` and safely update without discarding local changes. Enable
   hooks with `git config core.hooksPath .githooks`. Commit messages must be one
   Conventional Commit line. Pre-push also enforces the **500-line maximum**
   for Markdown guides in the pushed tree; changelogs are exempt. See
   [documentation policy](documentation.md).

3. **Verify prerequisites.** Follow the setup guide for full Xcode (the same
   version as the Mac that built the shared engine), the selected developer
   directory, Swift/SDK, Apple's Metal toolchain, Python 3.12+, Git, GitHub CLI,
   repository access and disk space. Complete available setup steps while user
   login or administrator authorization is pending.

4. **Connect to the shared engine.** On the home network, run
   `python3 scripts/engine_storage.py setup --share
   nfs://Tardis.local/volume1/parc-engine-nfs` from Terminal (or the app that
   will run releases). It saves the NAS settings, downloads the Metal toolchain
   if needed, mounts the share (allow the Network Volumes prompt), creates the
   engine's build folder with an administrator password and matches Xcode's
   file dates; turn on System Settings > Privacy & Security > App Management
   for that app first, or setup names it as still needed. It ends by listing
   anything left. The first release, or `python3 scripts/engine_storage.py
   workspace`, then unpacks the engine from the NAS and builds only what
   changed. See [shared engine storage](engine-artifacts.md#shared-engine-storage-on-a-nas).
   Without a NAS, the [archive restore](engine-artifacts.md) needs a published
   pin. Do not start a fresh Chromium sync/build or edit receipts to make an
   incompatible workspace appear valid.

5. **Run applicable inert checks.** Read the check scripts first. Run
   `scripts/check-swift.py` against the checkout's native bridge headers.
   Inspect restored package reports. Do not launch apps/browsers, take app
   screenshots, rebuild Chromium or package an app for onboarding.

6. **Report readiness and stop.** Store tool versions, actual paths, environment
   settings and check results in ignored `work/onboarding.md`. Report workspace
   restoration and completed-package availability separately. Preserve unfinished
   build state; restoration is not proof of a successful current build. Name any
   failed prerequisite and its next action, then stop before feature development.
