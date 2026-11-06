# Navigation responsiveness investigation

PERF04 remains LEFT. The first exploratory comparison used the running v240
component development package (app source `043b253f3b976b455abc32e134be263dc713b272`)
RAM. Each browser received a newly created private window and the same HTTPS
Wikipedia main-page URL. These were first visits within those windows; the
underlying process, network and system cache state was not reset. Concurrent
Swift compilations were running, the viewport sizes were unequal, and the
windows were active at different times. These observations are not a controlled
benchmark or evidence of a cause.

The page's Navigation Timing and Paint entries were read from the DevTools
console after load, with the console closed during the initial navigation.
Times are relative to each document's navigation origin, not Return key or
physical screen presentation:

| Browser | Response end | DOMContentLoaded end | Load end | First contentful paint |
|---|---:|---:|---:|---:|
| Parc v240 | 1.76 s | 15.87 s | 16.05 s | 15.74 s |

Both rendered the intended page. The observed initial Parc UI automation input
returned `noWindowsAvailable` and a subsequent state read timed out; the typed
URL appeared later and the process recovered. A three-second `sample` of Parc
PID 43743 at 16:56:41 local, before submission, shows main-thread samples in
Combine-delivered `BrowserWindowController.render`, `updateNavigation` and
`SidebarView.render`/layout and row construction. The sample contains concurrent
workload and cannot attribute the later page delay. Its raw local receipt is
`work/perf04-evidence/v240-private-preinput.sample.txt`, SHA-256
`83935e301a075fcefa46ccfb3017bdc290c8b1c3b0d396e6ebaf1c41e3f1ca07`.
The private store is ephemeral and does not run its own deferred session save.

The next comparison needs matched viewport and visibility, interleaved repeated
real HTTPS sites, recorded concurrent machine load, cold-context and warm
reloads, and both existing-page and new-page navigation. Record failures and
Navigation Timing/FCP separately from external Return-to-visible measurements;
FCP is not screen presentation and automation call latency is not a key event.
For any repeatable delay, sample the relevant application and renderer during
the delay, distinguish resource/network waits from processing, and identify the
actual boundary before changing behavior. The separate shipping configuration
performance requirement remains open; a component package cannot establish it.

## Metadata publication investigation

An additional sample of the same v240 process, captured while four
scrolling actions were attempted, is retained locally at
`work/integrated-polish-6b718f5c/parc-scrolling.sample.txt` (SHA-256
`2f8b91f3a192823ff1c034ae2b1346c6410a744587ef4d6c2a3e61e20acd9319`).
Its main-thread call tree includes Combine's queued window-state subscriber,
`BrowserWindowController.render`, `updateNavigation`, and construction and
layout inside `SidebarView.render`. It also contains substantial accessibility
request processing. The sample does not isolate scrolling, show which model
mutation caused a render, or establish the cause of the page-load delay.

Source inspection identifies one avoidable source of queued work during
navigation: each native title or URL callback invokes `BrowserStore.updateTab`,
which formerly assigned the published state separately for current metadata,
Today saved metadata and history. Each window's subscriber queues a render for
each publication but reads the latest state when delivered. The transaction
now publishes the tab and history changes together; normal split reconciliation,
selection stamping and save scheduling still run. This is a Parc implementation

`BrowserStore.scheduleSave()` was still encoding the whole pretty-printed
session on the main thread 0.25s after each `changed()`, including title/URL
ticks during load (`save()` at `BrowserStore.swift` ~4840). That delay is a
(`Engine/ParcNative/native_appkit_page.mm` ~938) states it is "not recovered
`JSONEncoder.encode`. The session JSON schema, ISO-8601 dates, pretty-printed
sorted keys, 0o600 permissions, atomic same-directory replace, 0.25s debounce
and ephemeral skip are unchanged; encode/write now run on
`org.parc.session-save` with generation cancellation and identical-snapshot
skips on the coalesced path. PERF08 stays LEFT. The
focused model check covers coherent publication, recent-history deduplication,
saved-pin destination and private-history behavior. A controlled real-site
comparison and a sample during any repeatable delay remain necessary to close
PERF04; scrolling remains a separate open measurement.

The native page's payload-free metadata notifications fan out through the
facade to capture, crash, title, URL and loading callbacks. Capture and loading
both currently refresh the main window's navigation and sidebar; Peek refreshes
on each callback. A single pending-notification flag is unsafe: a separate
queued task can intervene before a later notification, and the later callback
can retry work against the then-current page and owner. Preserve those distinct
notifications and the facade's revalidation while investigating a narrower
per-fanout reduction. These source observations are not a measured cause.

Sidebar favicon admission previously constructed the entire `visibleTabs`
array for every current or saved-icon request just to test one tab ID. The
request now checks the same live profile, Space, archive and tab-ID conditions
with a short-circuit search, retaining the exact-tab, owner and async result
validation. This removes that temporary array and avoids visiting remaining
tabs after a match; it does not establish a measured performance gain.

The sidebar also repeatedly projected the same eligible split groups from an
unchanging state: once for the active item and again for row construction, and
once per candidate item while building each hierarchy container. Each render
now shares its first projection for the active item and rows; each container
build shares its projection with its location checks. The projections retain
their existing admission and ordering rules, and are not cached across state
changes or callbacks. This removes redundant source work, not an established
cause or measured improvement in page-load time. PERF04 remains LEFT.
The whole-module Swift typecheck passed without diagnostics, and the existing
whole-split copy model check passed 52 assertions, including hierarchy ordering
and Favorite split placement. No browser test was run.
