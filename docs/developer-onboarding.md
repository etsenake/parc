# Developer onboarding

Complete this checklist on a new machine before starting feature work. Use the
actual checkout and local paths; paths recorded for the previous machine are
historical context. Onboarding does not claim or resume feature rows.

1. **Read the project contract.** Read [AGENTS.md](../AGENTS.md),
   [README.md](../README.md), [collaboration](collaboration.md),
   [parity](parity.md) and [development setup](development-setup.md).
   Use the current ledger for ownership and outstanding dependencies.

2. **Check the checkout.** Verify the repository, origin, branch and working
   tree. Fetch `origin/main`; update a clean checkout safely while preserving
   local changes. Do not reset or discard work to make setup easier.
   Enable the commit-message check once per clone; its worktrees share it:
   `git config core.hooksPath .githooks`. It rejects subjects that aren't
   Conventional Commits, which the release builds its version and notes from
   (see the rule in [AGENTS.md](../AGENTS.md)).

3. **Set up prerequisites.** Follow the setup guide to verify full Xcode,
   its selected developer directory, Swift/SDK, Python 3.12+, Git, GitHub CLI,
   repository access and sufficient disk space. Install missing prerequisites;
   request user input when login or administrator authorization is required.

   [the reference guide](../References/README.md). Use the configured modern
   Python interpreter to run `scripts/reference-artifacts.py fetch`, then
   `scripts/reference-artifacts.py verify`. If already restored, verify it
   instead of fetching over it. Check the restored app's signature at the path
   recorded in `References/arc-reference.json`. Set `PARC_REFERENCE_ROOT` to
   its absolute location so worktrees share the reference and slot pool.
   Exercise `components.py`, `arcidx.py`, `arctypes.py` and `arcfn.py` using
   [the documented examples](../scripts/arc/README.md). Keep the pinned reference;

5. **Restore the existing engine build workspace.** Follow the
   [engine artifact guide](engine-artifacts.md) to fetch the pinned archives,
   verify them and restore them to dedicated local paths. Preserve the existing
   compiled objects and build caches. The last completed app-and-engine package
   validate provenance and adopt the new workspace path. Do not start
   a full Chromium sync/build or manually rewrite receipts to make a copied
   workspace pass validation. Report the exact incompatibility if restore checks
   fail and complete the independent setup steps.

6. **Run applicable setup checks.** Inspect and run the documented inert tooling
   checks. When matching CEF headers are available, run `scripts/check-swift.py`
   with their explicit path. Inspect the restored engine package's report;
   do not rebuild Chromium for onboarding.
   Check optional REA/Node/Ghidra availability separately;
   do not start decompilation or browser tests just to validate onboarding.

7. **Record readiness and stop.** Save relevant tool versions, actual paths,
   environment settings, check results and unresolved dependencies in
   `work/onboarding.md`. Report reference-analysis, restored-package and
   workspace readiness separately. Distinguish successful restoration from a
   completed current engine build; retain any unfinished build state and do not
   compile merely to change that status. A missing archive or failed
   prerequisite means setup is not fully ready.
   Stop before feature development.
