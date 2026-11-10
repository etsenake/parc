# Navigation responsiveness

Controlled navigation and scrolling measurements remain part of the performance
backlog (PERF04). Earlier exploratory component-build observations used unequal
viewports, different activation times and concurrent compilation. They do not
establish current shipping performance or a cause of a reported delay.

## Implemented reductions in source work

`BrowserStore.updateTab` publishes title/URL, saved Today metadata and history
changes in one state transaction. Split reconciliation, selection stamping and
save scheduling still occur; subscribers no longer receive separate publications
for each piece of the same native metadata update.

Session encoding and atomic writes run on `org.parc.session-save`, with generation
cancellation and identical-snapshot skips. The session schema, ISO-8601 dates,
pretty-printed sorted keys, 0600 permissions, same-directory atomic replacement,
0.25-second debounce and ephemeral-store skip remain unchanged.

Favicon admission tests exact Profile, Space, archive and tab identity through a
short-circuit search instead of constructing `visibleTabs` for each request.
Asynchronous result/owner validation remains intact. A sidebar render shares its
eligible split-group projection between active-item and row construction; each
hierarchy container likewise reuses its projection. Nothing is cached across
state changes or callbacks.

These changes remove redundant work in source. They are not measured speedups
and do not, by themselves, close PERF04 or the separate persistence/performance
work represented by PERF08.

## Metadata publication investigation

Native payload-free metadata notifications fan out to capture, crash, title, URL
and loading refreshes. Notifications requery current state after validating their
original page/owner. Replacing them with one pending-notification flag can erase
a later retry that should run after an intervening queued task. Any further
coalescing needs to preserve those ownership and ordering semantics.

Historical process samples included window rendering, navigation/sidebar layout
and accessibility work; they did not isolate scrolling or prove a page-load
bottleneck. Do not turn those samples into a causal claim.

## Validation plan

When browser work is explicitly authorized again, compare shipping builds with
matched viewports/visibility, interleaved repeated HTTPS sites, recorded concurrent
load, cold contexts and warm reloads, and both existing-page and new-page
navigation. Keep Navigation Timing/FCP separate from physical input-to-visible
latency. Sample app and renderer during reproducible delays to distinguish
network/resource waits from processing before changing behavior.

Current model/compiler checks cover coherent publication, history deduplication,
saved-pin destinations, private-history behavior and hierarchy ordering. No
browser benchmark or runtime responsiveness result is established by this
cleanup; existing restrictions remain in [AGENTS.md](../AGENTS.md).
