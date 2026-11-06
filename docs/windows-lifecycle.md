# Windows and lifecycle

## Restoration reference and remaining work

`4e452201e483b5480c0403a9ef8566e10515cdcb78828622ff9032b202e29547`.
contains a window ID, focused Space ID, sidebar mode, per-item last-active and
creation dates, stay-on-top, sidebar width, window contents, style, expansion
state, collapsed pinned sections and optional platform data. Its container
These field declarations identify storage, not proof that every state is
restored in a particular launch scenario. `WindowContents.State`'s coding keys
its content validation remain to be traced. Sidebar width defaults are recorded
in [sidebar resize](sidebar-resize.md#width-across-relaunch).

identifier through an application action and uses `extendStateRestoration`;
in `restorableWindows` and reports an invalid Space before falling back to the
`softwareUpdaterWillRelaunchApp` and the second (case 4) to
`arc_quitAlwaysKeepsWindows`: the path returns true for the updater or the
unresolved supplied condition, otherwise returns the second default. The
supplied condition is inferred to be the Sentry client's `crashedLastRun` closure
from the copied field layout and call sequence; this is static inference, not a
preserve, close and system cases; the system case reads `NSQuitAlwaysKeepsWindows`.
The inspected toggle and AppDelegate paths do not use that getter, and any
separate synchronization between these settings remains unproven. The retained
particular macOS launch.

It ignores the `hasVisibleWindows` argument, dispatches AppDelegateAction
effect. With no key window, it resolves a window candidate from WindowsState;
miniaturized, otherwise `makeKeyAndOrderFront:`. If its window collection is
empty, the reducer creates a standard window. The candidate helper sorts
event's window ID and falls back through the supplied window collection when
the original window is unavailable. REA evidence
`ev_5878cc4a755fb1079d60bc81cbad187acd62d1a7525da28892375a08e0e825c9`
is raw-slice pseudocode checked against original instructions; Swift indirect
whose owner remains unresolved. The two selectors dispatch window creation

factory uses that style for `.browserPopup`, so the AppDelegate's ordinary

Parc's Dock menu exposes New Window and New Incognito Window through the
existing window-creation owners. The incognito action uses the existing
unresolved. Dock reopen leaves a current key window alone, otherwise chooses
the last active live browser window, falling back to the first live browser
window. It sends `makeKeyWindow` to a minimized candidate and
`makeKeyAndOrderFront:` to another candidate. With no browser windows it
creates a standard window without the New Window command bar. Closing or
unready windows are not candidates, and a still-retiring window does not cause
an extra window to be created; those guards are Parc ownership adaptations.
Setup and shutdown keep their existing lifecycle gates. The eight-case pure
decision check exercises these branches; no Dock input or browser test ran.

Parc records a stable ID, focused Space, selected items, focused pane, sidebar
mode, width and activity dates for each regular non-popup window. Its current
AppKit restoration path associates each standard window with that stable ID.
The implementation returns original windows by ID and leaves frame, minimized,
fullscreen and ordering restoration to AppKit; Parc does not force them to the front. An older
record or a launch without a system-restored browser falls back to the first
saved record. Unrequested and failed records remain across subsequent saves
rather than being replaced by a live window. A missing Space falls back to the first available
Space without borrowing another window's selection. Stale or differently
owned panes are removed by the existing presentation ownership reconciliation.
Older records without presentation fields keep their earlier single-window
fallback, and disabling session restore does not seed a saved window record.
domain, so AppKit keeps every window's state at Quit. `LaunchContinuity`
(`launch.json` beside the session file: whether the last run on this data was
still running, and the executable's modification date and size) then decides
which AppKit requests are accepted: every window after a crash or a changed
first at launch. Declined records stay in the session file but AppKit
forgets their windows at its next save, so they do not come back later. The
marker is written only once the engine has started, so a failed start or a
launch handed to a running Parc leaves the previous run's state. AppKit keeps
one saved-window list per bundle identifier, shared by every data root.
Private and popup windows opt out of AppKit restoration and private stores
remain ephemeral. Window identity/selection mapping and missing-Space fallback
follow the recovered contract; empty selection and unopened-record retention
are Parc data-preservation adaptations. AppKit restoration completion can occur
before or after the app's engine-driven launch, so a two-phase gate retains Dock,
external URL and relaunch requests until the original windows are ready. Parc's
save path remains in place. WIN12 continues the logout and launch-policy
comparison and integration with the independently owned focus and shutdown paths.
Apple's archived [termination guidance](https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/AppArchitecture/Tasks/GracefulAppTermination.html)
describes logout reaching `applicationShouldTerminate:`; it does not establish
whether an OS logout dynamically enters Parc's overridden `terminate(_:)` or
how that asynchronous override responds to logout. This remains unverified.
Runtime browser, logout and relaunch tests are not authorized.

## The same tab in two windows

Every window's sidebar shows the same tabs. Selecting one whose page another
window holds moves that live page into the selecting window, with no prompt.
The window it left keeps a frozen, dimmed picture of the page until the page
comes back.

### Reference contract

Swift type table and annotated disassembly; no decompilation.

  `SelectItemParameters.allowReparentingWindowContent` (+0x49) at
  returns two effects: a windows-level move request for the item, then the same
  (allowReparenting 1, isItemBeingAdded 0, moveFromOriginalLocation 0;
  window” string.
  host is `meet.google.com`.
- **The move.** `WindowsData.reparentWindowContent(for:from:to:trigger:)`
  `ReparentingTrigger.targeted(.itemSelected)`. The destination ingests the
  `IngestionInfo` carries `canRemainVisibleInSourceWindow`).
- **The window it left.** With `reparented-window-content-placeholders-enabled`
  `canRemainVisibleInSourceWindow`, the source content becomes Blueprint case 5
  screenshot shows that window's row unselected, its address empty and its
  `BlurredSnapshotView`: `ZStack(ForEach(snapshots) { Image.aspectRatio.frame
  the picture stays as it was when the page left; it is never refreshed.
  popover 0.7) with a `CASpringAnimation` on `opacity`: response 0.225 s and
  Josh's screenshot (live left pane against the frozen right one) gives
  opacity 0.58 to 0.60 over the theme's pink on all three channels.
- **The way back.** `ReparentingTrigger.untargeted(.itemDeselected |
  filter means “still holding a placeholder for the item” is inferred.
- **Not carried.** The move touches only window content (web or document
  state, find in page); it carries no modal state, so a Peek does not travel
- **Not persisted.** `PlaceholderState` and `Blueprint` conform only to
  `Equatable`; `WindowContent`'s coding keys are just `id`. Placeholders do not
  survive a relaunch.
- **Flags.** Both are LaunchDarkly flags whose built-in default is off; their
  server values aren't readable here (this Mac only caches Dia's flags). With
  second, separate page in the new window. Parc holds one live page per tab,

### Parc

- **Selecting moves.** Every selection route (a sidebar row, the command bar's
  Switch to Tab, Favorites including Option-click splits, Next/Previous Tab,
  Go to Sidebar Item, the recent-tab switcher and history cycling, Add to Split
  from the command bar or a pane's Add Split, a sidebar row dropped into a
  split, Reopen) moves the pages another window holds for the item, one at a
  time, then selects it. A split brings each of its panes. Notes and Easels
  move with their live editor. The invented “This tab is open in another
  window” dialog is gone. A move that can't start (a window closing, another
  move under way, the page in full screen) beeps and changes nothing; a Note
  or Easel that can't move beeps too, where a sidebar drop explains why. A tab
  another window claims with nothing behind it yet (a blank tab, a Note or
  Easel that failed to open) is simply handed over, leaving a placeholder. A
  page still being created has no holder yet, so it isn't offered. Moves are
- **The window it left** keeps the pane in its slot, sized as before and in the
  shows the page's last frame: a compositor copy of its viewport taken in the
  window it moved to (a copy needs the page visible in its key window), taken
  once as the page moves and never updated. The whole pane is at 0.6 opacity
  drawing. The engine's PNG is decoded off the main thread straight to the
  pane's pixel size. A capture the user starts takes the page's one capture
  slot back from that copy. Page commands don't apply to the pane. Clicking
  it, its row, or VoiceOver's press (its help says “Shown in another window.
  Press to move it here.”) moves the live page back: it continues exactly
  where it was, with no reload, and the window it left now shows its own
  frozen copy, taken at that moment. A window whose last page moved away stays open with its placeholder,
  including one the engine opened.
- **The way back.** When the window holding the page stops showing it, the page
  returns to the most recently active window still showing its placeholder,
  without activating that window. Each deselection is tried once; a refused
  return waits for the page to be shown and deselected again. When that window
  closes, before it asks its pages to close, each page another window shows as
  a placeholder moves to the most recent such window that can take it now,
  passing over one that would refuse; the close resumes after each move. A
  page that arrived for a split whose other page then refused to move goes
  back to its placeholder rather than staying here unseen.
- **Peeks** travel with their parent: both pages leave the same Browser in one
  native collection transfer, and the same Peek moves over with its page,
  state and observers. Parc's Peek is bound to its parent page, so unlike
- **Reopen and Close Undo** regroup a whole split even when another window
  shows its other panes; Reopen's selection then brings those pages here.
- **Row actions** work in every window: a click, VoiceOver's press, a split
  cell, a Library card's Open Tab and Go to Sidebar Item move the page here;
  rename, split titles and icons and Favorite rename change the shared item;
  and a row's Close, including a Library card's, moves the page here and then
  closes it here, so a leave-page confirmation appears in the window whose
  row was used and the close goes on its Undo and Reopen. A move that's
  refused beeps and closes nothing. The recent-tab switcher's close does the
  same, ending the switcher while the page moves. Actions on the live page itself (mute, reset) stay in
  the window holding it, which is the only window whose row shows them, as in
  page belongs to the first window that shows it.

Data safety: one live page per tab is kept by the shared page-ownership
registry, which reserves both windows' claims for the whole move and blocks
rendering, navigation and closing of that tab meanwhile. The engine moves the
real Chromium tab (`TransferLiveTab`/`TransferLiveTabs`): the same
WebContents, renderer, history, form state, audio and video picture in
picture. DevTools is keyed to the WebContents. The moved page becomes the
selecting window's focused page; the window it left has no view of the page
left to type into, and its frozen pane takes first responder when clicked, as
offers Retry, Close Page or Keep Open.

Adaptations and limits:

- Parc moves Notes and Easels through the window-move transaction, which needs
  both windows visible, unminimized and free of sheets; so does a page with a
  Peek. A plain page moves from a minimized window too.
  viewport after the move, so until it arrives (about a frame plus encoding)
  the pane shows its white backing at 0.6. A page copied in a window of a
  different size is scaled to fill the pane.
  deselected page only to a window showing its placeholder now, and a closing
  window's page to any window keeping one.

### Checks

`scripts/test-window-presentation.sh` (`WindowPresentationTests`): a page
that leaves keeps a placeholder with no selection or focus, across Spaces;
it rejoins its slot and split geometry when it returns; a closed or archived
partner, a newer selection or an archived page clears it; and the move and
return choices (`PageReparenting`), including passing over a window that
would refuse and trying each window most recent first, the shared row rule
(a row for another window's tab moves it here, and its Close moves it here,
then closes it), the claim owner lookup and that a window showing a
placeholder knows it isn't empty. `ClosedItemsTests` checks that a survivor
shown in another window rejoins a reopened split.
`scripts/test-close-undo.sh` keeps the busy-pane case and the Library card Clear whose pane goes back into its split.
`scripts/test-page-placeholder.sh` checks the frozen pane draws only its
snapshot, shown without animation, its VoiceOver help, that a picture is
kept at the pane's pixel size and never enlarged, that the capture's PNG
both springs; given Josh's screenshot
(`PARC_ARC_FROZEN_SCREENSHOT`) it renders the pane offscreen, with the live
No browser was launched.

## Stay On Top

items and inserts “Stay On Top” at index zero only when its view state's
`canStayOnTop` is true; its checkmark reads `stayOnTop`. Keypaths
values if absent. Otherwise it reads `PersistedWindowState.style` (field 47)
and `stayOnTop` (field 57); the capability is false for style tag 1 (`little`)
popup is Little-style. The menu click independently resolves the browser and

or the level captured by the initializer when false. `CodableWindowData`
encodes the field and decodes its absence as false. The action-73 jump-table
`PersistedWindowData`, and flips its `+0xf8` modify witness. For
`+0x10c` resolves to field 63, `stayOnTop`. The decoder places the Boolean
observations, not runtime relaunch acceptance.

Parc stores the Boolean in each regular window's identity-matched record,
defaults older records to false, applies it to that window's native level and
restores its own captured original level on disable. Private windows support
the live toggle but have no persistent record; popup windows are excluded.
The item captures its original window and revalidates that it remains the
selected live owner before acting. That captured-owner and closing-state guard
runtime browser or relaunch acceptance is claimed.

The window-presentation model passes 147 assertions, including both launch
gate orderings and deferred Dock delivery. The repaired session-store component
passes 29 assertions, including the
per-window date round-trip, subsecond precision and older ISO-8601 records.
ClosedItems passes 162 assertions, including the real-store same-second ranking.
The subsequently run, unchanged `SidebarResizeRegionTests` failed its
`recovered tracking options 0x227` assertion. Neither its implementation nor
its test is changed by the activity-date increment; the full check did not pass.
