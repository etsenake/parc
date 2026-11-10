# Native Chrome/AppKit host conformance

Browser/app launch is currently prohibited by [AGENTS.md](../../../AGENTS.md).
The runtime procedures below are retained for a future explicitly authorized
run. Source/model checks do not grant that authorization.

This harness is registered in the pinned overlay as `parc_host_harness`. It tests an upstream native-host capability separately from the production Parc shell. See the [ownership contract](../../../Engine/ParcHost/README.md).

Source checks, without launching an app or accessing a real profile/Keychain:

```sh
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s tests/EngineConformance/native -p 'test_*.py' -v
PYTHONDONTWRITEBYTECODE=1 python3 tests/EngineConformance/native/validate_overlay.py --source /absolute/pinned/chromium/src
```

The second command reads pristine pinned preimages and applies the actual overlay parser in memory. Once an overlay is applied, use the engine tool's recorded-overlay validation rather than treating the modified checkout as a pristine preimage.


Launch after a successful build, using a new path whose parent already exists:

```sh
python3 tests/EngineConformance/native/launch.py \
  --app /absolute/output/Release_GN_arm64/parc_host_harness.app \
  --profile /absolute/test-parent/native-host-01 \
  --url https://example.com
```


The initial window has normal Chrome controls plus an AppKit side panel titled **Parc native host**. Retained Chrome controls are intentional test infrastructure, not the proposed Parc UI. New tabs created from either UI must appear in both lists. The native address field accepts explicit HTTP(S), `chrome:` and `about:blank` URLs; search and normal browsing are available through Chrome's real omnibox. **Log identities** writes a JSON snapshot to the launching terminal, not to a remote service. CEF creation/close callbacks also print IDs. A missing panel, source CHECK, crash or incorrect identity is a failure; do not count a rendered page alone as a pass.

Required runtime record:

| Check | Pass evidence |
|---|---|
| Native host/window | Side panel is a real accessible NSView in the same visible NSWindow; resize changes page and panel geometry without overlap or a hidden second window. Snapshot attachment field is true. Native typing, selection, keyboard traversal and page input work. |
| Real tabs | Create at least three tabs with AppKit **New tab** and Chrome controls. Select each from both lists. Native/extension window ID and tab IDs agree, ordered indices are contiguous, exactly one tab is active, each actual tab has its own CEF host ID. Closing a non-active tab never clears the active page or another tab's host. |
| Navigation/rendering | Load a local fixture and real HTTPS page, exercise script/input, navigate Back/Forward/Reload and resize GPU content. Native model rows track actual active content. |
| Close consent | On a user-activated beforeunload fixture, **Close tab → Stay** retains that exact tab; a subsequent **Leave** closes it once. Repeat with native window close and ⌘Q. No premature row deletion, crash, stuck message loop or surviving helpers. The harness exits only after actual last-page close callbacks. |
| Native view lifetime | Close/reopen the host panel with Chrome's header/action UI, change tabs while hidden, close tabs, then close the window. No stale owner/model access; the reopened panel reflects real model state. |
| Extensions | Use `chrome://extensions` to load the [local MV3 fixture](../README.md), then its **real Chrome action**. Run its documented identity, scripting, command, worker, popup-window and profile-nonce procedures. Compare native snapshot IDs with fixture API output. Fixture PASS does not verify denied activeTab enforcement. |
| Restart | Cleanly quit; relaunch with `--reuse-profile` and confirm the fixture's known nonce/local storage survives. Independent profile directories must not share that nonce. |
