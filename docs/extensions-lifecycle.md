# Extension presentation lifecycle — EXT14

`4e452201e483b5480c0403a9ef8566e10515cdcb78828622ff9032b202e29547`.
The retained reports in
`/Users/josh/Documents/Codex/2026-10-23/re/outputs/parc/arc-extension-popup-presentation-contract.md`,
`native-extension-popup-lifecycle-plan.md`,
`arc-extension-popup-dialog-exceptions.md` and
`arc-extension-side-panel-contract.md` supply the existing ownership contract.
The recovered-component, Swift-type, cross-reference and annotated-function
helpers were consulted before implementation. No direct REA/decompiler call
or second-version comparison was needed for these findings.

## Popup opening, dismissal and motion

its controller, attaches the popup to the actual parent, positions it and calls
`makeKeyAndOrderFront:`. Neither this presenter nor its absence callback
callback calls the retained controller's `close` before clearing it. Parc keeps
AppKit's native window presentation and immediate terminal detachment; it does
not add an invented extension transition.

this popup's parent. Other windows or another application becoming active do
and the parent-key action both clear optional popup state through
`NSWindowWillMove` notification marks it user-moved; there is no custom resize
animation in that path. Geometry is covered by EXT12.

The existing Parc implementation already preserves these boundaries:

- `NativeExtensionActionContainer` has one current popup, immutable action
  model identity, generation checks, and separately retained terminal sessions.
  A close/unload/replacement callback cannot remove a newer popup. Active-tab
  change, original Browser deselection and shutdown end the current session.
- `NativeExtensionPopup` installs the real ExtensionView before renderer
  creation. A terminal request suppresses posted load/resize delivery. It
  retains the native view through modal-handler teardown, defers genuine host
  deletion out of engine and AppKit event stacks, and resolves the show callback
  exactly once. Parent-window close, supplied-page detachment and engine close
  share terminal cleanup.
- Load-before-show, explicit renderer focus, modal/DevTools holds, and browser
  security UI refusal are retained Chromium156 adaptations. They are not newly

## Site Control Center to extension handoff

Parc previously called `dismissSiteControlCenter()` and immediately dispatched
an extension action or context menu. AppKit could still be closing the native
popover when the popup became key. Its subsequent parent-key notification is
itself an established popup-dismissal input.

Dispatch now uses the native close completion. The controller retains itself
from `willClose` through `didClose`, because the window owner releases its
current controller during `willClose`. The window's separate
`SiteControlCenterDismissal` coordinator retains every still-closing controller
by identity; a second gesture cannot bypass an older native dismissal even
when a replacement popover has also begun closing. Every dismissal replaces or
cancels the pending action. A generation check also cancels an action after
`didClose` has queued it but before the next main-loop turn. The coordinator
owns this one dispatch queue; the native controller owns presentation only.

The window removes the matching Site Control Center session before calling
PageInfo's terminal close. A synchronous terminal rows callback consequently
cannot cancel the intended after-close action or close a replacement session.
Before dispatch it rechecks the original window, Browser binding, page wrapper,
real page, document revision, Space, key-window state and request generation.
Opening a newer Site Control Center or scheduling a newer extension request
invalidates the old generation. The original immutable engine action lease is
preserved; an extension ID is never looked up again to retarget the gesture.

## Side-panel event comparison and current adaptation

The retained original bridge owns one native side-panel wrapper per Browser
and carries existing WebContents. The Arc1.122 helper follow-up resolves the
previously unexamined `SharedWindowFeature.WindowAction.browserSidePanel`

  reads that native panel's title and writes `ADKClient.SidePanel` through the
  state setter at witness offset `0x1e8`. The type has only `browserID` and
  `title`; the passed WebContents is retained/released as event payload here.
  clears it (`0x1e8`), resolves its original browser's panel and calls
  completion in this bounded reducer path. The `withAnimation` payload has no
  branch or animator use there; its tagged event release only releases the
  panel object.
  metadata field offset `0xd8`, field 50 `sidePanel`. These are simple copies
  into the optional state, not presentation code.

visible motion. The follow-up now establishes the positive native gate and
construction boundary: key 14 maps to default-false `ExtensionSidePanelEnabled`,
and the native Browser features initializers leave the panel UI slot read by
the gated helper empty. The [side-panel compatibility contract](extensions-side-panel-adaptation.md)
records exact addresses, typed local overrides, provenance and the reason to
retain working current-Chromium panels as an explicit adaptation. It does not
rely on missing Swift types or claim every possible flag configuration is absent.

Parc retains its connected Chromium156 panel service: hidden attachment before
load, successful original-window/container validation before shown events,
identity-checked replacement, contextual cache and live tab movement, exact
extension unload/disable cancellation, synchronous native detachment and
asynchronous actual host/manager destruction before Browser/Profile release.
The native adaptation now has explicit user dismissal: EXT12's close header
calls `closeExtensionSidePanel()` on the original binding; the bridge refuses
background, detached, unselected or retiring Browser owners. An unhandled
plain Escape is accepted only from the panel's original key NSWindow after
session validation. Upstream's automatic Escape-close applies only to popup
hosts, so forwarding every panel key to the menu was insufficient. Both new
routes invoke genuine service close; they never only hide the app container.
The explicitly supplied panel-only focus scope includes the new close header;
weak scope identity, original-window attachment and current page ancestry are
validated before restoring the saved responder. Other controls keep their focus.
No invented close delay holds an engine-owned page alive to imitate an
unrecovered animation. Its native focus restoration additionally rejects a
hidden previous view or a disabled previous control, while preserving any
newer unrelated responder. That guard is an AppKit adaptation; it does not
claim equivalence with the app's separate offscreen-sidebar focus policy.

## Checks and evidence boundaries

Receipts are outside Git at
`/Users/josh/Documents/Codex/2026-10-23/re/work/extensions-checks/ext14/`.
The Site Control Center component check passes 47 assertions, including owner
release between native will/did-close notifications, final delegate release,
latest-action replacement, overlapping native closes, cancellation both before
and after didClose, and stale delayed-show rejection.
It hosts inert content and invokes native delegate boundaries; it does not
load or drive a browser. The final panel completion adds 23 inert AppKit event
and focus assertions, covering exact key-window ownership, modified Escape,
header focus, unrelated controls and detached or wrong-window pages. Both the
changed panel and AppKit host source pass their actual pinned Chromium target
(`panel-final-native.json`). Whole-module Swift typecheck and final SIL pass
with zero diagnostics (`ext14-panel-final.json`).
Independent review identified and drove the original close-coordinator
correction. Fresh completion reviewer `ext14_lifecycle/ext14_completion_review`
then cleared the complete native close/Escape/focus implementation and integrated
popup handoff, with no findings; `panel-completion-review.md` and
`panel-publication-inputs.json` retain the exact source hashes and clearance.

No functional browser tests, live keyboard acceptance or whole-product motion
acceptance were run. Source/compiler/component evidence is separate from
runtime acceptance. The positive native gate and construction evidence closes
the panel comparison through the documented current-Chromium adaptation; panel
