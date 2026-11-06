# Independent-engine extension conformance fixture

This self-contained Manifest V3 extension is a **test input**, not an engine implementation or a compatibility claim. It has not yet been run against Parc's replacement engine. Browser runtime checks belong in a disposable profile; keep reports under ignored `build/`, outside source control. A Chrome baseline can help separate fixture defects from backend defects, but does not establish Parc compatibility.

## Start and install

From the repository root, serve only the synthetic fixture directory on loopback:

```sh
python3 -m http.server 8765 --bind 127.0.0.1 --directory tests/EngineConformance/extension/web
```

Load `tests/EngineConformance/extension/` as an unpacked extension in the disposable browser profile. Pin its **Parc Engine Conformance** action. The action must open the supplied popup; a browser without extension installation/action support has not passed this gate. Do not navigate manually to another site's page for these checks.

All controls are explicit. **Create fixture window** creates one dedicated normal window at `http://127.0.0.1:8765/fixture.html` with a synthetic run token. Creating/focusing a tab or window can close the toolbar popup; reopen it to read the recorded result. In popup windows without a toolbar, use the action command: Control–Shift–9 on macOS, Ctrl–Shift–9 elsewhere, if bound. Configure an unbound/conflicting shortcut in the browser's extension shortcut UI before testing dispatch.

## Checks and exact pass criteria

| Check | Steps | Required evidence |
|---|---|---|
| Install / action | Load, pin and click the action. | Real extension popup and local report. Verify pin/unpin visually; this fixture cannot assert toolbar placement. |
| Native window / identity | Create fixture window. On its loaded page, reopen action and **Check tab / window identities**. | New nonnegative window/tab IDs; requested `normal` type; `windows.get(populate)`, `tabs.query`, `tabs.get` and active-tab results agree; every registered live fixture tab is present; contiguous indices starting at zero and exactly one active tab. Confirm a real native window visually. |
| activeTab / scripting | On that page click **Run activeTab script** twice. | Two PASS records from main frame 0; visible counter becomes 1 then 2. Injection requires the action's temporary grant, exact tracked URL/run token and page marker. An unrelated active page must report BLOCKED without changing it. |
| Navigation | **Navigate this fixture tab**, wait for load, reopen action and inject again. | Same tab/window identity; visible step toggles one/two; injection returns that step; counter restarted at 0 before injection. The navigate record alone proves only request acceptance. |
| Create / select / remove tab | **Create sibling tab**, reopen action there; check identities and inject. Then **Close this fixture tab**. | Distinct tab ID, same window ID, preserved `openerTabId`, active selection agrees; close produces matching `tabs.onRemoved`. Original page remains usable. |
| Actual popup window | From a fixture page choose **Create popup window**. Open the action with its shortcut there; check identities and inject. | Distinct window ID, type `popup`, real native popup window and working content. Close its fixture tab; original normal window stays open. This does not test page `window.open`, POST or opener adoption. |
| Event routing | Refresh local results after the above. | `EVENT` entries for known fixture `tabs.onCreated`, loading updates, activation and removal, with consistent IDs. No unrelated page URLs/titles are collected. An event entry is evidence of delivery, not a blanket PASS. |
| Commands | **Inspect command bindings**, close action, press Control–Shift–8 on macOS (Ctrl–Shift–8 elsewhere), reopen and refresh. | Nonempty custom command binding and a new `commands.onCommand` EVENT. The inspector alone does not prove shortcut dispatch. `_execute_action` opens the action and is not expected to emit that custom command event. |
| Worker suspend / wake | Ping and record `boot`. Close popup and extension DevTools. Let worker become inactive using browser diagnostics; then invoke the custom command and reopen the action. | Command event has a new `boot`, previous journal and fixture registry survive, and checks still work. Same `boot` means suspension was not observed, not PASS. No timer/port deliberately keeps this worker alive. |
| Persistent profile storage | In fresh profile A, **Verify fresh profile has no nonce**, then **Create profile nonce once**. Copy the synthetic nonce. Quit/restart normally; enter it and **Read / compare profile nonce**. | Immediate write/read PASS and later exact equality without a new write. Registry is session-only and intentionally empty after browser restart; create fresh fixture pages for further page checks. |
| Profile isolation | Install the same unpacked extension path in fresh profile B. Verify no nonce before creating B's nonce. Compare B's own value after restart; return to A and compare A's original value. | Fresh B has no A nonce, new B value differs, both profiles retain their own values. Do not confuse two windows in one profile with independent profiles. |

**PASS** means only the assertion named by that record succeeded. **FAIL** means a present API returned an error, timed out or contradicted an assertion. **UNSUPPORTED** means the required API/event is absent. **BLOCKED** means a prerequisite is unmet, such as the wrong page, still-loading page, missing action grant/URL or missing expected nonce. Unsupported and blocked are not passes. Save a local JSON report plus browser/version/profile and manual visual observations; do not report aggregate conformance until every applicable row has evidence.

There is no automated all-tests button. Reports contain the latest 200 records, worker/run IDs, synthetic profile nonce and only fixture tab/window identities. **Save local JSON report** downloads this data on demand. The worker stores the journal/nonce in `storage.local` and the live registry in `storage.session`; nothing uses `storage.sync`, fetch, network logging or telemetry. Uninstalling the extension removes its local storage. Close remaining test windows and stop the loopback server after testing. If an API times out, inspect the actual windows before retrying create: the browser may have performed the operation without returning its callback.

## Scope and guardrails

Permissions are exactly `activeTab`, `scripting`, `storage`. There are no host permissions, `tabs` metadata permission, history permission, declarative content scripts, external messaging, remote code, or remote resources. The worker registers event listeners at load but records tab events only for its session registry; it does not inspect arbitrary page content. Explicit identity checks query only a fixture-created window, require all registered live fixture tabs to appear, cross-check populated/query/get identities and discard untracked identities/metadata from the report. Page mutation requires the currently active tracked fixture tab and exact loopback URL; a tab navigated elsewhere is refused. Injection checks the URL again inside the document to handle a navigation race.

The activeTab check is a **positive grant-path test only**. The unrelated-page BLOCKED result comes from the fixture's own guard before it calls the scripting API. It does not prove the engine denies injection without a grant; an engine that ignores activeTab enforcement could pass that positive check. A separate controlled denied-injection API test remains required before claiming permission enforcement.


Chrome's [activeTab contract](https://developer.chrome.com/docs/extensions/develop/concepts/activeTab) supplies temporary user-invoked access; [tabs](https://developer.chrome.com/docs/extensions/reference/api/tabs) and [windows](https://developer.chrome.com/docs/extensions/reference/api/windows) document the identity APIs. [Commands](https://developer.chrome.com/docs/extensions/reference/api/commands), [service worker lifecycle](https://developer.chrome.com/docs/extensions/develop/concepts/service-workers/lifecycle), [scripting](https://developer.chrome.com/docs/extensions/reference/api/scripting) and [storage](https://developer.chrome.com/docs/extensions/reference/api/storage) define the remaining checks. The fixture uses those documented contracts; supporting them in Parc remains an implementation and runtime-verification task.

## Source-only validation

No dependency installation or browser is needed:

```sh
node tests/EngineConformance/extension/validate.mjs
```

This validates the restricted manifest, referenced files, JavaScript module syntax and positive/negative URL/ownership guards. It does **not** execute extension APIs or replace runtime evidence.
