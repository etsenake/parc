# Archive ownership and retention

## Automatic-archive settings and education — AUTO11

The Profiles pane uses the existing four visible choices: **12 hours (default),
24 hours, 7 days and 30 days**. Older 1-hour, 6-hour and Never values remain
readable as disabled saved choices; they are not added to the normal menu.
The row contains “Archive tabs after”, the information entry, and the recovered
180-point trailing picker. The extra invented status/help rows are removed.
dependencies are excluded. It explains the real Library → Archive → Put Back
route without performing an archive operation.

An interval change saves the selected original Profile immediately. When at
least two Profiles exist and their resulting intervals differ, the Settings
window offers the recovered two-button sheet:

- “Parc will now archive your tabs after [interval]”
- “Would you like to apply this change to all of your Profiles, or only your
  [name] Profile?”
- “All Profiles” / “Only this Profile”

Only this Profile leaves the already-saved choice alone. All Profiles atomically
updates the captured Profile set. A removed, renamed, newly added or changed
Profile, pending removal, replacement Settings selection or closed Settings
window revokes the retained callback. A failed save preserves the original
published intervals and uses the existing native Settings error sheet. The
shared interval also becomes the fallback for newly created/imported Profiles;
a per-profile change updates that fallback only when all Profiles converge.
Migration retains existing Profile values and the prior 12-hour creation default
when the new explicit fallback field is absent. It does not infer a global
choice from unrelated historical Profile values.

The genuine automatic-archive feedback is one shared sidebar education card,
not a sweep count toast, countdown, operating-system notification or progress
indicator. Its original text is “We cleaned up!”, the explanation about tabs
unused for 12 hours with an inline Settings link, and “Got it”. Parc substitutes
its own application name. The content uses a 12-point continuous corner, theme
`backgroundExtra`, a header with body-medium text at black/white 0.8 and a
black-0.08/light or white-0.05/dark wash, callout-regular body text, a body-light
button over theme `focus`, 12-point content padding and 8-point vertical button
padding. Its shadow is black 0.2, radius 1, offset (0, −1). The AppKit text/link
and button implementation preserves those roles; the owning sidebar host
supplies the recovered entrance/dismissal motion and focus lifetime under AUTO12.

Education eligibility is **false when absent**, shared application state, and
returning-user sign-in and ordinary launches do not arm it. Accounts are
excluded in Parc, so the explicit local adaptation arms education in the same
atomic write as genuine first local onboarding completion. Replaying completed
setup cannot rearm it. Loading an old Parc session with the field absent leaves
it ineligible. An already-completed legacy setup stays ineligible; an interrupted
first setup can arm only when the user genuinely completes it. Changing the
interval disables the fixed-12-hour education. Accepted nonempty
automatic archival consumes eligibility before publishing the transient shared
card; a native refusal, empty sweep or private store cannot consume or show it.
The transient card is not restored after restart. The Settings link has an
original-profile entry point that selects Profiles, reveals/focuses the interval
and refuses unavailable targets rather than using a remembered foreign Profile.

contracts, `components.py`, `arcidx.py`, `arctypes.py` and `arcfn.py` were used.
No direct REA or decompiler job was needed. Relevant mechanisms:

  original label, “Learn more about auto-archiving” info tip and 180-point width.
  it with the original, and requires at least two Profiles plus more than one
  map independently of the sheet result. Uniform values and All Profiles also
  `eligibleToSeeAutoArchiveEducationBanner`; `UserDefaultsClient` uses shared
  Returning-user sign-in skips this. Debug Reset EDU is a distinct true write
- Automatic `ArchiveFeatureAction` payload tag1 reaches
  requires no existing shared banner and bool(key66), constructs false/key66
  before the content effect, then enqueues content tag7. The original strings
  producer/effect-order facts, not claims about a new runtime observation.

Parc's durable model field, atomic settings snapshots, original-window refusal,
local help and first-local-setup arming are explicit independent-app adaptations.
The source does not add account/network/telemetry behavior. The sidebar's current
included banner is this education card; no unrelated product/service banner
was invented to reproduce the reference's shared-banner exclusion.

**Delivery/checks:** the producer, native card and Settings paths are integrated
with AUTO12's actual sidebar host and original-window callbacks. The fresh
AUTO11 reviewer cleared the exact source; the interrupted-setup documentation
clarification above was incorporated before integrated completion. Component evidence lives in
`work/automatic-archive-checks/auto11/`, with the separate key66 proof in
`work/automatic-archive-checks/education-default/EVIDENCE.md`. The file-backed
model checks pass 25 assertions, existing BrowserStore checks pass 796, and inert
native card checks pass 16 with disposable data and offscreen light/dark renders
at 144/228/500 points. The final warnings-as-errors whole-module SIL receipt and
source manifest are recorded beside them. No browser functional test, real preference/profile change, or runtime
appearance/physical keyboard acceptance is claimed.


Archive and History live beside the current page in its browser window. Opening the library does not unload, replace or reparent that page. The library captures the window's profile; switching that window to a different profile closes it. Search, deletion, clearing and restoration use that captured profile rather than BrowserStore's last-used global selection.

`LibraryView` provides date-grouped rows, title/URL search, Auto-Closed and Manually Closed filters, source-Space filters, selection, context actions and confirmed deletion/clearing. Return opens History or puts an archived item back; arrows and Shift selection use the native table; Delete requests confirmation; Command-C copies selected URLs; Command-F focuses library search; Escape clears search, dismisses filters, or exits. Archive and History share the category rail with Captures and Downloads. The current page stays beside it. The exact-profile native favicon service supplies database images; absent icons do not cause a Swift network request.



`ArchiveProvenance` records the closure reason and original Space identity/name. An archive record keeps its original profile when the source Space is reassigned. Existing records without provenance remain unknown; they are not silently classified as manual. A full set of Today panes archived together retains its split order, orientation and width factors. Partial closures retain individual tabs and cannot restore surviving live panes. Profile, URL, tab identity and saved tab state remain on the original BrowserTab records.

Put Back uses the selected source-Space filter as its destination. With all Spaces shown, it uses the initiating window’s current Space. A removed or reassigned destination falls back to that current Space only when it still belongs to the archived item’s original profile; no compatible destination leaves the original archive unchanged. The Library permits one source-Space filter at a time, matching the recovered filter enum. Put Back in Space supplies an explicit destination independently of the current filter.

The window validates every original group member against actual native ownership/retirement before changing the model. A complete split restores together with original IDs, pane order, orientation and ratios; no intermediate state restores only some siblings. History opens its stored URL directly. Reopen Closed Tab uses a distinct typed previous-Space policy and the most recent archived record in the initiating window’s profile. Its exact original stack/group-selection policy remains unrecovered; this increment does not change it or claim it is the Library policy.

Cleanup runs five seconds after initial browser presentation and on an independent 21,600-second clock with 2,160-second tolerance. It deletes only records whose archived date is at least 5,184,000 seconds (60 days) old, and removes their recent-closed references. It does not delete live tabs or browsing history, and does not change automatic-archive eligibility, protected-page checks or the persisted automatic-archive start time. App shutdown cancels delayed and periodic cleanup. Clearing Archive confirms the full profile scope, independent of active filters.

## Reference evidence and limits






## Automatic archive typed-item and window eligibility — AUTO09

The sweep projects the existing Today sidebar roots for each original Space and
Profile. A single browser tab, Note or Easel can expire; a split is one candidate
with its original ordered members and geometry. Every member must still belong
to that Space/Profile, be an unpinned Today item outside a folder, be read and
older than both the persisted start gate and that Profile's inactivity interval.
A protected, saved, malformed local-document or unavailable constituent preserves
the complete split. Folders and saved/Favorite roots never become independent
archive candidates. This uses Parc's existing typed sidebar projection rather
than treating every flat `BrowserTab` as a separate item.

The automatic close captures the original item reference, member IDs,
Profile/Space/placement, creation/document URLs and split record. The complete
snapshot must still occur in a fresh eligible-item projection immediately before
native unload. A same-profile move, navigation, regrouping, protection or policy
change therefore cancels the complete transaction. A title-only metadata update
does not change the original document. The existing once-only accepted native
retirement boundary still owns the model commit and archive provenance.

Each physical browser window contributes its own selected IDs, currently rendered
panes and pending native selection. This protects both sides of an asynchronous
presentation transition even if another window last published the shared model
selection. Selection protection is independent of occlusion. All retained Peek
sessions protect their original parent, including a hidden retained Peek; transfer
reservations and noneligible/unknown native page and embedded-Easel states remain
protected. `AppDelegate.runArchiveSweep` unions these windows and reads them again
at pre-unload admission. Existing pending-page, exact owner/page, document flush,
whole-window-close and actual beforeunload checks remain the retirement gate.

`4e452201e483b5480c0403a9ef8566e10515cdcb78828622ff9032b202e29547`.
Retained `native-analysis/auto-archive/fields.json` identifies
itemContainer/welcomeToArc/splitView/sharedObject/instantLinks/tabGroup.
(list, itemContainer, welcomeToArc, splitView, tabGroup) and retained payload mask
`0x8d` (tab, arcDocument, easel, sharedObject), with instantLinks also admitted by
without a timestamped, old-enough tab constituent. Candidate IDs then lose
identity and folds eligible children back into their original group. These are
static instructions and metadata, not runtime observations. Shared/service

Retained `exclusions-typed-evidence.json` binds current-content protection to
for the original sidebar ID map (`WindowContents.State + 0x68`). The current
content chain has no occlusion gate; its modal state is at `+0x50` and split IDs
at `+0x08`. The native trait/form/media evidence remains in the retained contract
and [ArchiveProtection notes](../tests/ArchiveProtection/README.md).

Parc's flat persisted Note/Easel tab records, whole-split conservative protection
for mixed legacy placements, malformed-document refusal, and immutable
pre-retirement snapshot are explicit adaptations to its source-owned model and
annotations and check receipts are retained locally in
`work/automatic-archive-checks/auto09/`; the component/index/type helpers answered
this comparison without a fresh decompiler session. The existing model suite adds
typed document/saved-root/mixed-split and original-item consent checks. Functional
browser and matched appearance/motion tests were not run under current direction;
AUTO10–AUTO12 retain their separate scheduling/presentation/interaction work.

## Automatic archive clocks, wake and occlusion — AUTO10

`ArchiveScheduling` owns the scheduled work; the application owns maintenance
and each physical browser window owns its own activity subscription. Initial
browser presentation schedules an archive sweep after one second and retention
cleanup after five seconds. Independent periodic effects run at 300 seconds
with 30 seconds of tolerance and 21,600 seconds with 2,160 seconds of tolerance.
Each window starts its 60-second activity clock with 60 seconds of tolerance
after initialization and cancels it when its actual pages finish closing.
Closing one window never cancels another window's activity. Repeated starts do
not duplicate a subscription; weak owner and unique subscription guards reject
queued callbacks after cancellation, replacement or owner destruction.

Recurring work uses Swift's `ContinuousClock`, preserving elapsed time while
the Mac sleeps. It resumes the outstanding deadline on waking and coalesces
missed periods using the reference iterator's nominal-deadline calculation.
The app does not issue a second archive sweep, reset the persisted eligibility
start time, restart the clocks or stamp every visible tab merely because a
workspace wake notification arrived. The separate launch delays use the main
dispatch queue. Every callback mutates the model on the main actor, and
maintenance declines to run during the existing asynchronous termination
transaction. Shutdown cancels all pending launch and recurring work. Retaining
the normal schedules across a declined quit preserves the existing close/consent
owner rather than treating a pending quit as completed shutdown.

Activity samples the actual window's `.visible` occlusion bit on its tick;
missing, closing and occluded windows contribute no IDs. App activation and
key-window status are not timer eligibility gates. Every rendered split pane
in a visible window is timestamped in that window's original store. An
occlusion notification continues to settle Sidebar motion and refresh native
payment controls, but does not itself change last activity. Explicit selection
and initial-presentation activity paths remain, and current/selected/pending
pane protection stays independent of occlusion under AUTO09. This distinction
keeps a hidden current page protected without pretending the user viewed it.

`4e452201e483b5480c0403a9ef8566e10515cdcb78828622ff9032b202e29547`.
The retained `native-analysis/auto-archive` evidence, component/type/index
helpers and annotated functions establish these facts without a new REA session:

  cancels both named periodic IDs. Parc also cancels its owned launch callbacks
  so no queued work can reach an app that has completed native shutdown.
  whole late periods using the ceiling of the overdue-duration ratio.
  Parc uses the same continuous-clock deadline policy rather than converting
  these recurring effects to an uptime-only dispatch timer.
  60/60 subscription under `itemLastActiveDateUpdateTimer`. Its timer action
  rejects both absent (2) and occluded (1) before calling activity update
  checks `NSWindow.occlusionState & 2`; no key-window gate occurs there.
  `AppAction.macLifecycle` (case 40), `lifecycleEventEnded` (case 2),
  `computerSleeping` (event 0). Screen wake uses the same route with event 1.
  own active events, event dates and the auto-update idle timer; they do not
  send Archive actions. Vendor auto-update tracking remains excluded.

Parc's first-ready-browser admission (onboarding must finish first), explicit
initial-presentation activity stamp, private-window stores, main-actor native
consent guards and cancellation of pending launch effects are adaptations to
The comparison covers static ownership, clock semantics, cadence and event
routes; real OS sleep/occlusion and browser runtime were not exercised under
the current no-functional-browser-test direction.

The focused component command is `bash tests/ArchiveScheduling/run.sh`. It
compiles only this scheduler and its test harness, with no AppKit window,
engine, profile or real OS sleep. The 26 assertions cover recovered schedules,
late-deadline coalescing, one-shot/recurring delivery, duplicate admission,
stale callbacks, destruction and independent window ownership. Whole-module
warnings-as-errors typecheck and final SIL receipts plus their input manifest
are retained under `work/automatic-archive-checks/auto10/`.

## Automatic archive interaction and education motion — AUTO12

Automatic closure removes the accepted background items from their original
window without selecting another tab, changing its Profile/Space, opening the
Library or activating a browser window. The existing native retirement owner
continues to require whole-set acceptance; the education presentation cannot
commit an archive. Removing a parked pane now leaves the window's rendered list
unchanged. Only removing an actually rendered pane invalidates that list and
rebuilds the split container; a background archive no longer forces unchanged
selected pages through detach/rebuild on the next render.

The once-only education event uses the shared regular-store publication from
AUTO11. Each eligible regular browser window presents its own card below the
sidebar list, above the dock. The card stays in that physical window and never
reparents a native page. Profile/Space changes refresh its local action context;
private/pop-up windows cannot offer it. Ordinary metadata, activity and palette
updates keep the same card and do not restart its presentation. The link and
Got it button join the sidebar's native key-view chain only while the card is
interactive. A hidden sidebar or Space-creation surface disables their actions;
the hidden sidebar's existing key-chain bypass remains authoritative.

Appearance does not request first responder. Dismissal leaves an outside
responder unchanged; if the disappearing card itself owns focus, the original
window's existing content-focus owner resolves its current selected page. The
Settings link performs only an explicit user action and opens the real archive
control for its captured Profile in Settings, then dismisses the shared
education state only after that destination is accepted. Its captured
Space/Profile must still be current in the same key window and no attached
sheet may own the action. It never routes through a newly frontmost window.
Closing the physical window cancels queued appearance and dismissal work without
clearing another window's shared pending event.

### Recovered motion and lifetime

`4e452201e483b5480c0403a9ef8566e10515cdcb78828622ff9032b202e29547`.
The recovered-components, Swift-type, cross-reference and annotated-function
helpers answered this scope; no new decompiler session was used. Their focused
outputs are retained under `work/automatic-archive-checks/auto12/`.

- `SidebarBanner.State.PresentationState` is `appeared(Date)`, `initial`,
  Parc uses these same SwiftUI primitives around the native card, rather than
  approximating the spring with an arbitrary duration.
  common dismissal reducer keeps the state for 0.7 seconds before delegate
  space while the 0.25-second card exit completes.
- `ViewAction.didAppear` schedules `_transitionToAppeared` with zero delay for
  timeout. Hover therefore does not change education lifetime.
- `AutoArchiveEducationAction` has only `didClickDismiss` and
  same dismissal. No additional automatic-archive confirmation or Undo control
  is inferred from these producers.

Parc's AppKit layout slot above the dock, the keyboard link/button chain,
Profiles-pane deep link to the captured profile's actual Archive control,
original-window focus fallback and Reduce Motion snap are explicit adaptations
Generation checks prevent an old scheduled exit from removing a newer card;
window detachment, destruction and a reduced-motion change settle owned work.
The independently counted Archive/History selection, filtering, put-back,
preview and transition gaps remain in that family; AUTO12 does not credit them.

The inert `tests/AutoArchiveEducation/check.sh` creates only native component
windows, with no browser or engine. It checks original-responder preservation,
real native-card attachment, focus relinquishment, repeat-update stability,
disabled hidden controls, reversal/old-completion rejection, detach/reattach and
window-reset cancellation. This and the whole-module compiler checks establish
and browser functional acceptance remain unclaimed under the current direction.

The integrated AUTO09–AUTO12 source at base `03e343c7` passes the whole-module
warnings-as-errors typecheck and finished-tree SIL check (27 seconds, no
diagnostics). Receipts, the 333-file source/header manifest and the inert host
check log are retained in `work/automatic-archive-checks/auto12/`. Both independent
AUTO11/AUTO12 reviews cleared this integrated source before publication; their
review receipts are retained in the same row-specific evidence directories.

## Library search appearance pass — October 29

The regular Archive and History views reuse the same plain native search

## Archived Tabs page header — October 31

Archived Tabs and History now use the Downloads page header's components:
`DownloadSearchField` inside `DownloadSearchBackdrop`, which places the field,
and the `.header` `DownloadFilterButton`, sized by `fittingSize.width`. They
are laid out with `LibraryPageHeader`: an 8-point page inset on both sides,
top 10, height 36 and a 3-point field-to-Filter gap. The header is identical
to the Downloads header, in light and dark, idle, hovered and typed. It
had its own field with GrayA11 typed text and a chip-style Filter. The
placeholder ("Search Archive…" or "Search History…") is set on the shared
field, which draws it in the system placeholder colour; typed text is
primary. In the expanded filter, Done is `PageFilterView`'s own label with
12-point padding ([header notes](download-library.md#original-library-search-composition)).
The list, chips and empty state keep their 10-point trailing edge. Search,
Escape, Return and Down-arrow behaviour is unchanged. The component check
asserts the shared controls, header frames identical to Downloads, Filter and
Done padding, and the placeholder and typed ink across theme changes.

## Archive filter presentation increment

The Archive filter replaces the search header with “Filter Archived Tabs” and
Done, followed by closure and Space chips; the original query remains owned by
its search field. Space choices follow the current same-profile Space order,
existing product scope. The selected Space continues to own Put Back's
destination. Retired Space choices are cleared instead of silently continuing
to filter on a removed identity.

type metadata identifies the Archive reducer's `selectedSourceFilter`, one
`activePageType` (`all`, `autoArchived`, `manuallyArchived`), ordered Spaces,
and the shared `PageFilterView` state. The retained annotated helper
selecting the active chip clears it, and selecting the other replaces it. The shared PageHeader timing is
documented in `docs/download-library.md`: its 0.3-second cubic curve is used
for this header/list transition. AppKit controls, sizing, focus restoration,
Reduce Motion, composition admission and resize/owner invalidation are Parc
adaptations; appearance observation does not establish functional parity.

The reviewed filter integration passes the actual Library/view component (464
assertions), selection (39), entry/file-provider (44), and Library entry (230)
checks at base `5c82ccf8`. After the separate Media search integration, the
whole Swift module also passes warnings-as-errors typecheck at base `b6d3e716`
with zero diagnostics. These component checks use disposable data and do not
establish a runtime or visual parity result.

## Archive row interaction evidence — October 29

uses `PageItemsContainerReducer.State<ArchivePage.Tab>` and its optional
single-item selection. The shared container's Up/Down, including Shift, moves
that one cursor; Parc's existing multiple-selection table is not that contract.

The Archive row's shared `ContentCell` body-click callback
`SharedArchiveFeature.Action.didSelectItem`. The reducer resolves it to the
actual archived item and sends `onSelectedToPreviewItem` through
refuses list and tab-group data, re-resolves an ordinary tab in the current
not a particular snapshot panel or final visual presentation. Parc's current
double-click direct restoration remains a documented mismatch.

for the invoked original row. Restore passes that row's previous Space ID; its
original-window destination contract is above. Delete dispatches the original
ID through SharedArchiveFeature's action and async task
to `ArchiveDataStoreClient.unarchiveItems`; the attributed menu-to-storage path
has no confirmation. This does not establish Clear Archive behavior. The
current confirmed plural deletion, Put Back in Space and Copy Address are Parc
adaptations and are not evidence of the reference menu. A current-source
implementation and runtime comparison remain open; no action was executed for
this trace.

The closure-filter increment passes the actual Library/view component (470
assertions), selection (39), entry/file-provider (44), and Library entry (230)
checks. Its populated disposable Archive records verify the All → Auto → Manual
→ All row projection; the whole-module warnings-as-errors typecheck also passes.

### Regular Archive row menu correction

The regular Archive row now builds only Restore and Delete for the invoked
original item, independently of the selected table cursor. Restore passes that
row's previous Space to the existing window-owned Put Back callback, which
falls back to the initiating window's current compatible Space when needed.
Delete directly removes all members of the original archived item. History,
Clear Archive, footer and keyboard behavior are unchanged by this increment.

The menu captures the physical window and the complete archived member values,
including dates and provenance. Its synchronous state lease permanently expires
if any member changes or disappears, even when the same ID is rearchived at the
same timestamp. Category changes and window detachment also permanently expire
the menu; dispatch checks the current window owner, active Profile, profile
removal state and live grouped item again. These are Parc safety adaptations,
disposable records to check original-row targeting, group deletion, direct
execution and stale owner, category, window, member and rearchive refusal. It
does not establish live browser or visual acceptance. The row-click preview and
other Archive/History requirements remain open.

### Archive single cursor

Archive uses one table cursor: Up and Down, including Shift, move among displayed
items without wrapping or selecting date headings, and table Select All is
disabled. The row context menu still acts on its original invoked item without
changing that cursor. History keeps its existing multiple selection. The shared
container's optional selection and key behavior are attributed above and in
[Downloads selection](download-library.md#original-single-item-selection-and-direct-removal);
the AppKit table and its responder integration are Parc adaptations. This
increment does not implement the distinct Archive row-preview path.

The offscreen Library view and selection components passed 497 and 39
assertions with disposable data. The enclosing check wrapper was stopped during
its unrelated entry compile, so no complete wrapper pass is claimed. These
checks do not establish browser runtime or visual parity. The 279-source
whole-module warnings-as-errors typecheck passed on base `d6f4d363` with
unchanged inputs; the subsequent upstream favicon optimization does not change
the Library cursor interface.

## Archive preview retirement boundary

Archive deletion, Clear Archive and expiry retain the exact affected archived
item snapshots through native retirement. The complete intersecting split item
is reserved, even for a partial ID deletion; overlapping retirement requests
cannot supersede that reservation. Refusal or changed snapshots preserve the
records. Document deletion uses the same boundary for archived aliases. Without
a native retirement owner the existing model-only operations remain synchronous.

A preview lease names one ordered archived item and prevents competing preview,
ordinary restore and Profile-removal staging. Its identity tolerates mutable
content edits but requires the original archive membership and provenance.
Native retirement must compare the leases intersecting its ID set against the
exact live preview owners at admission and consent, refuse missing or creating
owners, and keep each lease until its original preview is destroyed. On success
it releases the leases before reporting completion; an unreleased lease prevents
the model deletion from committing. Preview promotion uses the lease-specific
restore operation and consumes the lease only on successful model restoration.
That restore publishes state synchronously: the window must suppress normal render
and preflight the exact native attachments and ownership before calling it,
because a failed page transfer cannot safely roll back the published record.
These are model and integration contracts; browser runtime behavior is not
established by the model checks.
