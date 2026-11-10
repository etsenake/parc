# Archive ownership and retention

Library's Archived Tabs page belongs to the initiating window and Profile.
Opening it leaves the selected page attached beside it; changing Profile closes
Library. History opens Chromium's `parc://history` in a new tab. Parc's separate
visit index, used by the command bar, follows Chromium history deletions.

## Archive records and restoration

`ArchiveProvenance` retains closure reason and source Space identity/name.
Records retain their original Profile even if that Space is later reassigned.
Legacy records without provenance stay unknown. A complete Today split archived
together retains member IDs, order, orientation and ratios; a partial closure
stores only the closed tab and cannot restore surviving live panes.

Put Back uses the chosen source-Space filter as destination. With all Spaces
shown, it uses the initiating window's current Space. A removed or reassigned
Space falls back only to a current Space in the record's original Profile;
without one, the archive remains unchanged. An explicit Put Back in Space action
supplies its own destination. A saved tab restored to its original Space returns
to its original folder if that folder still exists. Other destinations, removed
folders and Today items restore at top level; deleted folders are not invented.

The native retirement/ownership gate validates the whole item before model
mutation. Complete splits restore atomically. Reopen Closed Tab has a separate
previous-Space policy; see [closed-item restoration](reopen-closed-tabs.md).

## Archive filter presentation increment

Search matches title and URL. The expanded filter replaces the header with
**Filter Archived Tabs**, Done, closure chips and same-profile Space chips.
Only one closure filter and one Space filter are active. Clicking the active
closure chip clears it; another replaces it. Removed Spaces clear their filter.
Spaces with no records still appear. Filter presentation does not overwrite the
search query. The header uses the shared 36-point search/filter controls with
8-point page insets, top 10 and a 3-point gap; list content keeps its 10-point edge.

### Regular Archive row menu correction

Each 56-point row exposes Restore and Delete for the invoked original item,
independent of the table cursor. Restore uses that item's previous Space with
the compatible fallback above. Delete immediately removes that item's members;
Clear Archive confirms its full Profile scope regardless of active filters.
Hover/selection also exposes trash and Put Back, with equivalent accessibility
actions. Menu leases expire permanently when any member, archive provenance,
category, window or Profile changes, including same-ID rearchival.

### Archive single cursor

Up/Down, including Shift, move one cursor without wrapping or selecting date
headings. Select All is disabled. Return performs the item's action, Command-C
copies URLs, Command-F focuses search, and Escape clears search, dismisses
filters or exits. Row activation uses the implemented [archive preview](archive-preview.md)
owner; it is no longer the old double-click-only restoration path. Exact-profile
native favicon lookup uses the database and never adds a Swift network request.

## Automatic-archive settings and education — AUTO11

Settings → Profiles offers **12 hours (default), 24 hours, 7 days and 30 days**.
Legacy 1-hour, 6-hour and Never values remain readable as disabled saved choices.
Local help explains Library → Archive → Put Back; it does not archive anything.

An interval change saves its original Profile immediately. If at least two
Profiles then have different intervals, Settings offers **All Profiles** or
**Only this Profile**. All Profiles atomically updates the captured set. Added,
removed, renamed or changed Profiles, removal staging, a changed Settings
selection or a closed window revoke the callback. Failed saves preserve the
published intervals. A shared interval becomes the fallback for newly created
or imported Profiles; a per-profile change updates it only when all converge.
Migration does not infer a new fallback from unrelated historical values.

Education eligibility is shared app state and false when absent. Genuine first
local onboarding completion arms it atomically; replay and old completed setups
do not. Changing the interval disables the fixed 12-hour explanation. Accepted
nonempty automatic archival consumes eligibility before showing **We cleaned
up!**, its Settings link and **Got it**. Refusal, empty sweeps and private stores
cannot consume or show it. The transient card is not restored after restart.

## Automatic archive typed-item and window eligibility — AUTO09

The sweep projects Today roots in each original Space/Profile. A browser tab,
Note or Easel may expire; a split is one candidate. Every member must be an
unpinned, read Today item outside folders, older than both the persisted start
gate and its Profile's inactivity interval. Protected, saved, malformed or
unavailable members preserve the whole split. Favorites and folders are never
independent candidates.

Before unload, the original member IDs, placement, URLs, Profile/Space and split
geometry must still appear in a fresh eligible projection. Moves, navigation,
regrouping or protection/policy changes cancel the transaction. Title-only edits
do not replace the document. Native whole-set close consent owns the model commit.

Every physical window contributes selected, rendered and pending-selection
panes, protecting both sides of presentation transitions. This protection does
not depend on occlusion. Retained Peeks protect their parent, including hidden
Peeks. Transfers and unknown native/embedded-page states remain protected.
`AppDelegate.runArchiveSweep` rechecks the union before unload.

## Automatic archive clocks, wake and occlusion — AUTO10

| Work | Initial delay | Repeating interval / tolerance |
|---|---|---|
| Archive sweep | 1 second after first ready browser | 300 / 30 seconds |
| Retention cleanup | 5 seconds | 21,600 / 2,160 seconds |
| Per-window activity | After window initialization | 60 / 60 seconds |

Recurring work uses `ContinuousClock`, retaining deadlines through sleep and
coalescing missed periods. Wake does not add another sweep, reset eligibility,
restart clocks or stamp every visible tab. Callbacks run on the main actor;
termination cancels all launch/recurring work only when shutdown completes.
A declined quit keeps normal schedules. Subscription identity rejects stale
callbacks; closing one window does not stop another's activity clock.

Activity ticks stamp rendered split panes only when their original window has
the `.visible` occlusion bit. Key status and app activation are not gates.
Occlusion notifications do not themselves stamp activity. Current-page archive
protection remains independent, so a hidden selected page stays protected.

Cleanup deletes records at least 5,184,000 seconds (60 days) past `archivedAt`,
including their recent-closed references. It never deletes live tabs/history or
changes the automatic-archive start gate.

## Automatic archive interaction and education motion — AUTO12

Background archival neither selects another tab nor activates a window, opens
Library or changes Profile/Space. Removing a parked page does not rebuild the
rendered split. The shared education event displays a per-window card below the
sidebar list and above the dock; private/pop-up windows do not show it.
Metadata/palette updates reuse the card. Hidden sidebar and Space creation
disable its actions and remove them from the active key chain.

The card enters with bottom movement/opacity, response 0.6/damping 0.4 spring;
exit uses 0.25-second ease-in and retains its layout slot for 0.7 seconds. It has
no automatic timeout. Reduce Motion settles it immediately. Generation checks,
detachment and window closure cancel stale transitions.

Appearance does not take focus. Dismissal preserves outside responders or
returns card-owned focus through the original content-focus owner. The Settings
link validates the same key window, current Space/Profile and absence of a
sheet; it dismisses education only after Settings accepts that destination.

## Archive preview retirement boundary

Deletion, Clear Archive, expiry and document deletion retain exact item snapshots
through native retirement. Complete intersecting splits are reserved even for
partial-ID deletion. Overlapping requests cannot supersede the reservation;
refusal or changed snapshots preserve records.

A preview lease names one ordered item and prevents competing previews, ordinary
restore and Profile removal. It tolerates content edits but requires original
archive membership/provenance. Retirement checks exact live preview owners at
admission and consent, refuses missing/creating owners and holds leases until
those owners are destroyed. Leases must be released before model deletion.
Promotion consumes its lease only after successful restore. Because restore
publishes synchronously, the window preflights native ownership/attachments and
suppresses ordinary rendering before calling it; a failed transfer cannot undo
already published model state.

## Checks and limits

Model suites cover typed items, split atomicity, settings snapshots and original
consent. `tests/ArchiveScheduling/run.sh` covers clock ownership/coalescing;
`tests/AutoArchiveEducation/check.sh` covers inert card focus and lifecycle.
Library components cover filtering, original-row menus and stale leases.
These checks do not establish live sleep/wake behavior, keyboard/VoiceOver or
browser appearance. Current open product work belongs in [the backlog](backlog.md).
