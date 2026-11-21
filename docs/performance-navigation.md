# Navigation responsiveness

This guide describes the work boundaries that keep navigation metadata, session
persistence and sidebar updates from repeating expensive operations. Concrete
reported defects belong in [the backlog](backlog.md).

## Metadata publication

`BrowserStore.updateTab` publishes title/URL, saved Today metadata and history
changes in one state transaction, and skips identical updates. Split
reconciliation, selection stamping and save scheduling still occur.

Native metadata notifications are payload-free and requery current state after
validating their original page and observer. The producer compares shell-visible
state before posting unchanged shell/loading updates. `PCBrowserView` separately
compares capture, crash, title, URL and loading values before notifying Swift.
Favicon-only notifications use their own callback.

Notifications leave the engine observer stack through nonnestable tasks. Keep
that ordering: replacing all pending notifications with a single flag can lose
a retry that must run after an intervening queued task.

## Session persistence

Session encoding and atomic writes run on `org.parc.session-save`. Debounced
writes skip identical snapshots; explicit saves and profile-setting commits wait
for durability. Both preserve ISO-8601 dates, sorted pretty-printed JSON, 0600
permissions and same-directory atomic replacement. The debounce is 0.25 seconds;
ephemeral stores do not persist sessions.

History lives in a separate file beside the session and is written only when it
changes. Title, selection and activity updates no longer re-encode all stored
visits with the session. Explicit saves still recreate a missing session file.

## Sidebar and Library work

Favicon admission checks the original Profile, Space, archive state and tab
identity with a short-circuit search. Asynchronous results revalidate their owner.
A sidebar render shares its eligible split projection between active-item and row
construction; each hierarchy container likewise reuses its projection. Reused
rows retain settled artwork while their favicon identity is unchanged.

Library catalogs compare their relevant inputs before filtering and sorting.
Downloads refreshes only changed rows when item identities and section positions
are unchanged, preserving other thumbnails, selection and preview ownership.
See [Downloads](download-library.md) for its separate deferred investigation.

## Tab lookups

`BrowserState.tab(_:)`, `tabIndex(_:)` and `containsTab(_:)`, with optional
`where:` filters, answer exactly as a first-match scan of `tabs` would. States
the store publishes carry a lookup from tab identity to position, built on first
use and reused while the order of identities is unchanged. Any write to `tabs`
drops it, so edited copies, states without one and lists with repeated
identities fall back to the scan. The lookup is never saved or compared.
`openTabs`, `openTabs(where:)`, `containsOpenTab(where:)` and
`archivedTabs(where:)` read open and archived tabs from lists the lookup keeps
in `tabs` order, so open-tab views skip the archive; without a lookup they run
the same single filter as before. `tests/BrowserTabLookupTests.swift` checks
all of these against plain scans through random edits.

## Checks and measurement

`tests/ParcCoreTests/Data/Store/` covers coherent metadata publication, history
storage and deduplication, saved destinations and private-history behavior.
The Downloads view Swift Testing suite checks that unrelated store updates keep
the displayed row and selection, and that progress refreshes the original row.
The Library view harness also covers shared catalog reload guards.

For an authorized browser performance investigation, use shipping builds with
matched viewports and visibility, interleaved repeated HTTPS sites, recorded
concurrent load, cold contexts and warm reloads, and both existing-page and
new-page navigation. Keep Navigation Timing/FCP separate from physical
input-to-visible latency. Sample app and renderer during a reproducible delay to
distinguish resource waits from processing before selecting a change.
