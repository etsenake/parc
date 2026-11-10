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

3. **Verify prerequisites.** Follow the setup guide for full Xcode, the selected
   developer directory, Swift/SDK, Python 3.12+, Git, GitHub CLI, repository
   access and disk space. Complete available setup steps while user login or
   administrator authorization is pending.

4. **Restore the saved engine workspace.** Follow
   [engine artifacts](engine-artifacts.md). Verify the pinned archives and let
   the restore tool validate provenance and adopt the new local path. Preserve
   compiled objects and caches. The completed app-and-engine package is a
   separate artifact. Do not start a fresh Chromium sync/build or edit receipts
   to make an incompatible workspace appear valid.

5. **Run applicable inert checks.** Read the check scripts first. When matching
   CEF headers exist, run `scripts/check-swift.py` with their explicit path.
   Inspect restored package reports. Do not launch apps/browsers, take app
   screenshots, rebuild Chromium or package an app for onboarding.

6. **Report readiness and stop.** Store tool versions, actual paths, environment
   settings and check results in ignored `work/onboarding.md`. Report workspace
   restoration and completed-package availability separately. Preserve unfinished
   build state; restoration is not proof of a successful current build. Name any
   failed prerequisite and its next action, then stop before feature development.
