# Window activation and interrupted import

The application-menu importer retains its original browser and its destination.
New Tab now refuses while the importer or a native sheet attached to it owns the
key context. Closing an importer returns its original browser to the front only
if the import still owned the key context at close, the application remains
active, and the original browser is still visible, ready and unobstructed. If a
different window has become key during cleanup, the return is discarded. Closing
a background importer or retiring its parent cannot activate a different window.

`4e452201e483b5480c0403a9ef8566e10515cdcb78828622ff9032b202e29547`
has separate `newWindowForTab:` owners. `ImportDialogSheetWindow` at
restore a miniaturized window and activate the app. These are static facts;
they do not establish the exact importer close-focus policy or every other
auxiliary command. Parc's key-owner checks, disabling the menu item and the
conditional focus return are explicit ownership adaptations, not a claim of
window and native security admission before raising a browser; the separate
app-level fallback and its candidate selection remain to be compared.

The existing per-window focus and cross-surface contracts are in
[Navigation](navigation.md#focus-traversal-across-page-controls-and-auxiliary-contexts)
and [Keyboard navigation](keyboard-navigation.md#cross-surface-traversal-and-return).
WIN13 remains LEFT pending the rest of its activation, auxiliary-window and
interruption comparison. The import focus component checks exercise a hidden,
minimized or sheet-obstructed parent, inactive app, background close and
intervening key window without driving a browser.

Command–W targets Settings while that window is key, and refuses while its
availability and menu title are not inferred from the selector body.

For other auxiliary windows, the selected-tab fallback requires the original
browser to own the key context and to permit its close; a sheet, unrelated key
window or retired browser cannot receive an implicit Close Tab. The ordinary
own controller. Parc's explicit key-context guard is an ownership adaptation.

## Existing interruption owners

The following comparisons are retained from their owning deliveries, rather
than inferred from a foreground-window lookup:

  resignation; Parc also cancels on parent key loss, sheet, miniaturization,
  close and ownership changes as explicit native-security adaptations. See
  [held-input interruptions](tab-switcher.md#held-repeated-and-interrupted-input--kb22).
- Settings remembers weak per-pane responder identity, ends recording on key
  loss, and restores only its original visible, key, active sheet-free pane.
  toolbar and window owners are attributed in [Settings](settings.md#settings-responder-ownership-and-interruption--set26).
  becomes key. Other app/window activation is not evidence of the same rule.
  Parc's security/renderer holds are distinguished in [extension lifecycle](extensions-lifecycle.md#popup-opening-dismissal-and-motion).
- Per-window content focus, command-bar close, Peek and chooser return retain
  their original content/window owners as described in [Navigation](navigation.md#focus-traversal-across-page-controls-and-auxiliary-contexts).

These bounded contracts do not by themselves resolve every application-modal
and auxiliary-window combination, focus timing, or integrated behavior.

`didResignKey(Date)`, `didBecomeMain`, `didResignMain`, application resignation
action; these are separate from focus requests. Parc's browser callback updates
its last-active owner on a ready key window. WIN12 owns the Dock/reopen and
restoration behavior; the remaining WIN13 investigation must compare the
window-level lifecycle effects and modal admission without assuming that a key
notification alone moves a responder.
This does not rule out other composed reducers responding to those actions.

The separate Dock reopen and window-history contract is owned by WIN12 and
recorded in [Windows and lifecycle](windows-lifecycle.md#restoration-reference-and-remaining-work).

Settings pane from `SettingsTabViewController`'s optional `activeTab` and `panes`
pane, and checks the returned target or the pane's supplemental target for
`respondsToSelector:`. The annotated-function helper failed on an unmapped
address, so these operations were checked in the bounded original instructions
and the index's selector references. This does not establish the answer for
every action or permit treating the last browser as the Settings pane. Remaining
WIN13 work is to compare the specific browser actions that Parc's AppDelegate
currently resolves through its last-active fallback when an auxiliary owns key.
`navigateTabBack:` and `navigateTabForward:` selectors are implemented by
index found no other implementations of those six exact selectors. Stop
in that index. Parc's menu validation and dispatch for these window-scoped
commands now require the browser itself to be key and reject an attached
sheet. An owned command panel retains its own actions; this menu route does not
claim an untraced panel-dismissal policy. Zoom additionally checks the existing
original-page eligibility. The explicit key/sheet gate is a Parc ownership
adaptation; this comparison does not establish every auxiliary pane's individual
action policy.

The first increment's import focus and Settings-close inert components pass.
The combined Swift tree at `bc0d421f` plus the reviewed increment passed both
whole-module typecheck and SIL with zero diagnostics; the subsequent clean
fast-forward incorporated other owners' separately checked, unrelated source.
An independent reviewer cleared the exact WIN13 source. These checks do not
establish integrated browser or focus behavior.

The 1.122 method index also identifies only MainWindowController implementations
of `reopenLastTab:`, `resetTab:`, `resetVisiblePinnedTabs:`, `duplicate:` and
its owned command panel, and rechecks the same key window and original step
after panel, chooser and Library dismissal. Duplicate and Pin require the key
browser. Reset already checks the actual key window in `canResetSavedTab`, and
Reveal checks `spaceCommandsAvailable`; their existing per-command lifecycle
and consent checks remain authoritative.

Command-bar presentation now checks its physical key owner before cancelling
any existing split insertion, Space creation, capture or command panel. Its
owned command panel or history chooser may be key; dismissing that exact child
returns to the original browser, which must pass the existing native key/security
admission. Each intervening callback revalidates the original live owner before
further teardown. The original browser binding's existing read-only
`canParticipateInPageTransfer` admission checks its registered window and native
security reservation even while its child is key; it performs no transfer. A
key split-insertion panel returns key status only to its original live parent
interrupted-panel sequence is not inferred. The inert owner-sequence component
covers owner, key and security changes during synchronous cleanup callbacks.

The lifetime increment passed the inert owner-sequence component and the
whole-module typecheck at `178d366d` plus its reviewed changes. The subsequent
clean fast-forward preserved those changes while incorporating other owners'
separately reviewed source. Independent review found the sheetless reservation
and split-panel return gaps; both were corrected and the full revision cleared.
No browser behavior was tested.

education and command-panel owners for plain Copy, while requiring the key
browser for Markdown and Quote. Browser and command-panel menu paths recheck
the original registered window's native security admission. Education rechecks
that same original-window security gate and the available original page, URL and
view state before dispatch; its native command-window copy gate remains the final
authority. Exact menu validation of renderer availability requires a read-only
command-window native admission API, which is still a dependency. Sidebar
selection keeps its captured command owner.

`newSpace:` and `editSpaceTheme:` have only MainWindowController
Parc's menu actions now require the actual key, normal, non-private browser
and its native security admission. Their menu validation also uses the Space
creation and theme-editor admission and original anchor. The same normal-window
restriction applies to Pin. These are explicit key-owner adaptations; they do not establish every
menu's dynamic appearance or the exact behavior of an owned child panel.

validation and dispatch now require the original key browser and native
security admission for these three commands. Native Cast's own presentation
also rechecks its key parent; its separate non-key eligibility is preserved for
other owners. These are Parc ownership adaptations, not a complete claim about

The Manage/Add Extensions menu actions use their original key normal browser;
input resolution retains its original window, Space and Profile and rechecks
key/security admission before applying the result, including after synchronous
cleanup. The Site Control Center retains its exact window, page, revision,
Space and Profile through delayed presentation. Its Extensions footer retains
that same context and rechecks the key/security owner after native dismissal
and, for a normal browser, through input resolution. The popup footer's
cross-window handoff still needs a hidden-destination security preflight and
original-page lease; it is not claimed complete. These interruption guards are
Parc adaptations.

### Native admission handoff for WIN13

WIN13 needs two read-only, main-thread facade queries, with independent source
review before publication. The dedicated engine owner alone applies, builds and
packages the resulting native overlay; the WIN13 owner integrates the published
interfaces and retains the row until its own work is complete.

- Essentials Copy needs the existing `CopyCommandWindow` plus `CanCopy` plain
  URL admission exposed as a non-mutating query for the exact page, binding and
  command window. It must use the same original-selection, visibility, security,
  live-renderer and committed-URL checks as the existing copy operation, without
  writing the clipboard or weakening that operation's completion checks.
- Popup footer handoff needs a read-only registered-window/security admission
  for a newly created hidden destination: engine ready, active app, exact binding
  and window registration, no close in progress/approved, no attached sheet,
  no native security reservation and no miniaturization. Unlike the existing
  `canParticipateInPageTransfer`, it must not require visibility or key status.
  It must not authorize transfers or show/order a window. WIN13 will capture the
  source page/Profile/Space and destination window/Profile/Space, create a
  page-empty destination hidden, recheck this query before first show, then
  revalidate both owners after every presentation callback and through input
  resolution; a different key window or any invalid lease cancels the action.

The popup footer remains on its prior handoff until that interface is available.
The existing visible-destination gate is unchanged; neither query is runtime
acceptance or permission to run functional browser tests.

The native facade now exposes `page.canCopyURL(fromCommandWindow:browser:)`.
It constructs the same exact-page `CopyCommandWindow` and uses the existing
plain-URL `CanCopy` admission, without starting a copy or writing a clipboard.
`binding.canAdmitHiddenPageTransferDestination` checks the registered binding's
engine, app, close, sheet, reservation and miniaturization gates without a
visibility or key requirement. It neither performs nor authorizes a transfer.
Both are main-thread queries and their result is a momentary admission, not a
lease; WIN13 must revalidate its captured owners across callbacks. The
dedicated engine owner must apply, build and package the published overlay
before these interfaces are available in a delivered engine. WIN13 remains LEFT
until the consuming integration and its remaining requirements are complete.
Pinned Chromium-flag syntax checks passed for both changed native units, and a
Swift typecheck confirmed the facade signatures. These checks do not establish
runtime behavior.
