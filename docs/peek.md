# Peek ownership

Peek keeps an unsaved original `PCNativePage` and one `PCBrowserView` inside its source window. The native navigation adapter supplies the actual source-page relationship and Peek disposition; the shell never reconstructs a renderer request from its URL. The source profile, source tab, physical window and native binding must agree before adoption.

`PeekController` owns the temporary presentation and browser delegate. `BrowserWindowController` retains sessions by exact page identifier and source-tab identity, separately from saved tabs. Selecting another tab or Space hides that presentation without disposing of the document. Returning to its parent reveals the same page. Selected/visible page callbacks expose the real Peek to native security, page tools, extension/payment presentation, media and fullscreen ownership. The parent remains visibly rendered behind the scrim; a Peek page entering tab fullscreen is first promoted to a tab.

Close uses `requestClose`; a rejected beforeunload leaves the same page open. The original Peek confirmation owner evaluates the dismissal mechanism and current pending reason before requesting close. A fresh Escape requesting confirmation uses Close even while capturing; a fresh pointer, swipe or Close Tab dismissal uses Hang up while the original page is capturing microphone/camera input. A pending Close prompt can be confirmed by any existing dismissal entry. A pending Hang up prompt requires Escape, native Exit, Close or Close Tab: repeated background clicks and right swipes retain that prompt, increment its attempt count and restart its deadline, even if capture has since ended. The count does not impose a later automatic-close threshold. Parent retirement adds all unsaved Peek children to the existing whole-set Chromium retirement transaction. A Peek protects its parent from automatic archiving. Independent parent destruction promotes a still-live child to Today rather than orphaning it. Moving a parent to another physical window requires closing or expanding its Peek first.

The original Peek owns a `PeekDismissalConfirmation` work item. An unanswered Escape prompt resets after one second; an active microphone/camera prompt resets after ten seconds. Replacing the prompt cancels its previous deadline. Hiding the Peek, beginning its real close request or finishing the owner clears the prompt and cancels pending work. Expiry resets the pending reason and attempts, collapsing the confirmation control only: it does not close, navigate or move first responder. A weak owner and generation check prevent a queued callback from touching a retired or newly armed presentation.

Expand creates a saved Today record and reparents the same browser wrapper; Add to Split adds that record to the existing split selection. Attachment refusal restores the existing Peek container. No path calls `loadURL` to promote or restore. Address-bar requests inside Peek use genuine native search classification for the exact page/profile, while page links keep their original native navigation context. The normal failure presenter, capture leases and native page tools also operate on this unsaved page.

## Promotion return ownership

Accepted Expand and Add to Split now record the retained modal's original sidebar source in both `referrerID` and `activeTabBeforeCreationID`. The original page, actual Profile and physical native binding must still agree. Only after the same browser wrapper attaches and its saved-item claim succeeds does the initiating window replace its referrer pool with the promoted ID and source ID; it does not union unrelated creation chains. A refused attachment/claim leaves the prior pool and original Peek intact. Ordinary close consent then uses the existing source-owned return selection; a surviving split pane keeps precedence. Admission-only document metadata is not used as the ongoing modal parent after navigation.



## Open in current Space command

`openTabIn`, Command–O and `promptAfterConsumedByWebView` (Use Both), with no
`arcTypeTravelID`. This is a menu/Shortcuts command, not a command-search result.

the same arguments. There is no chooser or separate destination argument here.

The resolver first checks `source.window`, then the focused content ID's sidebar
identity and source-to-modal map. Thus ordinary sidebar Peeks qualify. The
without a destination or when its Space has disappeared; otherwise it supplies
“Open in [Space]” and a 12-point Space image. The earlier claim that a
window-sourced modal or missing chooser was required was disproved by this trace.

Parc's menu and Expand control now use the original Peek and the current physical
window's active Space, after checking the original Profile and native page.
A global Favorite viewed in another same-Profile Space therefore promotes there,
not into the Favorite's stored source Space. The original page attachment and
claim rollback, source referrer, modal return pool and focus ownership remain
with the existing promotion transaction. Orphaned-page preservation retains its
separate source-Space policy. A tracked menu command captures its original
modal/destination/window, revalidates on dispatch and cannot substitute a newer
target. The native security, sheet and marked-text gates remain authoritative.
The menu and Expand hint follow binding change/removal/conflict/reset; the
new default never steals another saved customization. Inert AppKit/registry and
actual store/presentation checks cover these contracts; browser execution and
final appearance/motion comparison remain unclaimed.

## Reference and adaptations





## Interaction map

| Interaction | Implemented state/ownership | Reference or explicit remaining gap |
| --- | --- | --- |
| Native page-link entry | Actual new foreground contents retain the original source; automatic pinned/favorite classification remains separate from explicit Shift/new-window link handling. The latter preserves the complete original request and base navigator. Refusal retains ordinary upstream behavior. | Recovered FrameCreationInfo and genuine renderer-decision routes. Eligible ordinary current-tab links use the one-use admission below; matched current-tab ATC and live authentication URL-lock state are connected. Modified/new-content routing and process restoration remain open. |
| Card and controls | Centered live card; close/expand/split; split disabled at four panes, during close and fullscreen; native button focus and activation | Recovered modal host/control families. Actual installed Peek geometry and hover/pressed appearance were not observed. |
| Close button / background / Close Tab | Reason-aware original-page close consent; an awaiting Hang up survives repeated background/swipe while explicit Close/Close Tab confirms. Pending controls disabled; beforeunload cancellation preserves the page | Recovered parent reason/attempts reducer and unload rejection. Chromium owns beforeunload. |
| Escape / media input | The exact focused renderer's main-thread Escape acknowledgment supplies consumed/editable state to the original confirmation reducer. Consumed or editable input requests Close; an unconsumed noneditable Escape requests direct close. A subsequent Escape confirms either pending reason. Native-control Cancel uses the separately recovered Exit mechanism. Unanswered prompts reset after 1/10 seconds; owner changes cancel pending work without moving focus. | Recovered native Exit and renderer heuristic producers are distinct. Pinned Chromium's acknowledged RawKeyDown is an explicit completion-boundary adaptation; no raw shell key monitor or synthetic acknowledgment remains. Exact owner/document/IME/security guards precede admission and deferred delivery. |
| Address / Copy URL / Find / Zoom | Actual Peek URL; exact-profile native classification; page-bound search lease; independent zoom state; Find Escape belongs to Find | Current page-backed routes. Native shortcut priority is preserved; original modal expand/key-binding mapping is not recovered. |
| Expand / split / tab or Space selection | Same wrapper promoted into saved Today/split with original source provenance and accepted replacement of the window-local referrer pool; hidden retained session on parent deselection; same original page on return | Recovered parent/content IDs and modal expand/split actions. Background-promotion fallback on independent parent destruction is a Parc policy. |


Appearance inspection is bounded to the actual reference surface. Links settings were directly observed; the page's link menu had no Peek action, and a Shift-click yielded an ordinary window. Those observations establish neither Peek trigger policy nor Peek visual parity. No haptic behavior was observed or invented.

## Original current-tab links

The native page opts its actual WebContents into a default-off renderer policy. Before Chromium creates its NavigationRequest, an eligible activated, outermost HTTP(S) link queries existing native/shell state while retaining the original WebNavigationInfo. A negative answer continues the exact original BeginNavigation branch. A positive one-use document/request token accompanies Chromium's genuine OpenURL transport, security validation and original-page Peek adoption. The shell reads pinned/favorite, selected Space and current/saved host state; native code applies the nine recovered website-authentication exceptions. No request is cancelled and replayed from a URL.

The policy query is synchronous and strictly limited to materialized state. It must not present UI, read storage, create a profile/page, wait, nest a run loop or call a renderer. Weak frame/document ownership plus renderer and browser sequence guards reject reentry, replacement, stale replies and consumed tokens. Actual creation occurs after the query returns. This one IPC round trip is a disclosed current-engine adaptation; latency equivalence is not established.

The eligible new-tab route preserves normal OpenURL request fields, including body, referrer, initiator identity and security callback. It does not claim identical BeginNavigation transport: download-sandbox/ad, script-injection, inherited origin-trial and deferred-commit requests retain their original branch; source-location/input timing and renderer cancellation ownership differ. Forms, history, reloads and client redirects are not rerouted.


## Authentication continuation lifetime

The exact live WebContents owns an intrinsic or authentication-unlocked state. A URL update to a different host that matches the recovered authentication classifier retains the previous source URL as its baseline. Intermediate authentication hosts keep that baseline. Returning to its host, or the actual eligible pinned/favorite item's saved URL host, restores intrinsic state. Missing transition information leaves the prior state unchanged. While unlocked, ordinary pinned-tab navigation stays out of automatic Peek. No timeout or per-document reset is invented.



## Native Escape ownership





Validation covers 51 isolated production-state/event-ownership assertions and 79 actual confirmation matrix/timer assertions, plus the native unit and full Swift application compiler. It does not establish browser runtime or historical Peek appearance acceptance. The existing real beforeunload/retirement route remains the only page-close operation.

## Original responder entry and return

Peek page focus uses its physical window’s registered native responder manager. The exact page must still belong to the same Browser/binding, be the actual selected original page and remain attached/visible in an active key window without a sheet, reserved security surface or context menu. A request does not select a page or activate a window. Existing renderer descendants and native text selection are preserved; accepted or pending focus is not reported as actual renderer focus.

A one-use weak responder return protects the asynchronous shell boundary. Initial presentation cannot override a newer control. After a refused close, the actual original control or renderer editor keeps focus; after actual dismissal, return targets the surviving original parent; after expansion/split, it targets the same original child after reparenting. A different concrete responder permanently cancels the return, including another control inside Peek. Temporary nil/window focus during teardown is admitted only with fresh original page/session/window/security validation. Owner loss, hidden Peek, changed selection or sheet never chooses a replacement target. The existing deferred native page-host callback separately requires the original window/renderer and still-owned host firstResponder, so later native controls and renderer replacement supersede queued work too.

