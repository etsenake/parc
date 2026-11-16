# Private navigation creation lifecycle

Every private window of a Parc profile shares one genuine primary off-the-record
(OTR) Profile: the private session that holds its cookies, sign-ins and site
data. It must exist exactly while something uses it, and Chromium must destroy
it as soon as nothing does. A URL-only replay or a fallback to the normal
Profile can never stand in for it.

## How private windows are created

- **New Private Window and scripting** go through the app's
  `createPrivateWindow`. `preparePrivateBrowsing(profilePath:completion:)` loads
  or checks the normal parent, waits out a session that is still being torn
  down, and runs its completion, which builds the `BrowserWindowController`
  whose `beginPrivateBrowsingWithProfilePath:error:` obtains the primary OTR
  Profile and creates its Browser in the window's one-use reservation.
- **Chromium-originated opens** keep Chromium's original request: the page
  menu's Open Link in Incognito Window, an extension's
  `windows.create({incognito: true})`, Chromium's own new-incognito command, and
  popups, DevTools and picture in picture from private pages. Chromium creates or
  finds the primary OTR Profile and calls `Browser::Create`; Parc's admission,
  `PrepareNativeBrowserWindow`, sends it to `PrepareAppKitWindow`, which prepares
  the private session (native route, search, private downloads) when this is its
  first Parc window, and the app's private `BrowserWindowController` adopts the
  request.
- The page menu item lands in the right window by Chromium's own choice: the
  most recently active private window of the same profile gets the link as a
  front tab; with none, a new private window opens. Another profile's private
  session is never used. It never reaches a normal window: Chromium disables the
  item for addresses that cannot open privately and when private browsing is
  disabled, and a refused private window opens nothing.

## The claim ledger

[`private_session_ledger.h`](../Engine/ParcNative/private_session_ledger.h)
holds the accounting with no Chromium dependency. A claim is a move-only RAII
token counted per normal parent Profile; it releases exactly once when it is
destroyed, reset or overwritten. `native_browser.mm` instantiates it with a host
that reads real Profiles and the Browser collection.

- `beginPrivateBrowsing` holds a claim for its whole body, from before the OTR
  Profile exists until its Browser is registered or the attempt fails.
- Admission holds a claim for every Browser of a Parc profile's primary OTR
  Profile. The claim travels with the window reservation into `NativeBrowser`
  and is released in `OnRegistered`, after the Browser has joined its
  collection, or when admission refuses.
- `preparePrivateBrowsing` and the delayed page-menu open hold a claim and a
  registry lease on the parent while they wait, and through the continuation
  that creates the window.
- Native operations keep using `NativeProfileLease` on the OTR Profile.

The existing deferral hook decides last-window teardown. When a private
session's last Browser leaves, `DeferNativeOTRProfileDestruction` keeps it if any
claim or lease exists and records it as pending; otherwise Chromium destroys it
at once, as before. Failed creations and refused admissions do not destroy
anything themselves: they nominate the session for the same deferred path. The
profile registry also nominates every new primary OTR Profile of a Parc profile,
which catches Chromium paths that create a session and then fail before asking
for a window, such as an extension's malformed `windows.create`. When a pending
session loses its last claim or lease, one retry is posted. The retry ends it
only if it is still alive, not already closing, has no Browser, no claim and no
lease, and it goes through the `DestroyUnusedOTRProfile` call-in, which consults
the deferral again.

## A session that is still closing

Chromium marks a session as shutting down the moment teardown starts but keeps
it as the profile's primary OTR Profile until its renderers exit, for up to
about a second. A window opened on it would be destroyed underneath itself, so
admission refuses every Browser for a closing session and adoption checks the
same. New Private Window and the page menu item wait instead: they park with
their claim, a small marker on the closing Profile posts a notice when Chromium
destroys it, and the waiter rechecks and continues with a fresh session. A
notice that arrives while a session is still closing keeps the waiter parked.
An extension's `windows.create` cannot wait, because Chromium's API answers
synchronously, so it gets an error during that moment.

Quitting closes the ledger to new waits: a request made while quitting fails at
once. Requests already parked stay parked: if the quit is cancelled at a
leave-page prompt before the old session ends, they continue; once the old
session ends during a quit they complete as failed. Their registry leases hold
the engine's idle check until then, which Chromium's destroyer bounds to about a
second. The app itself cancels its pending New Private Window requests when a
quit starts, so this matters for the page menu's delayed open.

## Invariants

1. Every claim is released exactly once, on success, failure, cancellation,
   quit, a destroyed creator, reentry or a removed or disabled parent.
2. A session is never torn down while it has a Browser, a claim or a lease, and
   no window ever opens on a session that is closing.
3. Nothing outlives its use: once a session has no Browser, claim or lease,
   its teardown starts within one posted task.
4. A waiter completes exactly once. It is never told the profile is ready while
   its old session is still closing or once quitting has started, it runs while
   still holding its claim, and a page-menu open is dropped if its page has
   navigated away meanwhile.
5. Claims for one profile never hold another profile's session, and Parc
   nominates only primary OTR Profiles; other OTR Profiles stay with their
   owners.
6. Hot paths are unchanged: no timer, polling, extra IPC hop or copy. Opening
   a link adds one disposition comparison; creating a private window adds a
   counted map entry; waits are event-driven.

Reentry is safe by construction. `beginPrivateBrowsing` marks its binding as
creating, so a nested begin or adoption on that binding refuses; a nested
creation elsewhere takes and releases its own claim; the ledger snapshots its
state before every host callback and rechecks claims after each one.

## Caller trace

| Path | Claim | Failure | Release |
|---|---|---|---|
| `preparePrivateBrowsing` | parent claim and lease across the wait and completion | quit, parent removal or disabled private browsing completes with an error | after the completion returns |
| `beginPrivateBrowsing` | parent claim for the whole call | nominates the session it obtained | at return |
| Admission of any private Browser | parent claim inside the reservation | refusal nominates the session | `OnRegistered`, refusal or Browser destruction |
| Page menu open while closing | parent claim and lease while parked | source page or document gone, quit or removal drops the request | after the reissued open returns |
| Opening a page in a private window | OTR lease | unchanged | lease destruction retries |
| Quit | `SetQuitting` refuses new waits; parked waiters complete when the old session ends | a cancelled quit lets them succeed | shutdown checks the ledger is idle |

## Checks

`bash scripts/test-private-session-ledger.sh` compiles the ledger with plain
clang and runs every listed sequence against a simulated Chromium world:
overlapping creations, both teardown orders, failure at each step, reentry,
quits that go ahead or are cancelled, destroyed creators, a disabled parent,
operation leases, abandoned sessions that are still closing, spurious end
notices and four thousand randomized interleavings. It checks the invariants
after every step.

`ParcPrivateSessionsTest.*` in
[`tests/NativePrivateSessions`](../tests/NativePrivateSessions/private_sessions_unittest.cc)
exercises the integration with real Profiles: claims deferring last-window
teardown, abandoned sessions, refused admission of a closing or unservable
session, and the host's view of a session Chromium is destroying. It reaches
Chromium's `unit_tests` through `//parc:page_preferences_tests`, so no Chromium
build file changes. The waiting paths need Parc's profile registry, which
Chromium's shared unit-test processes cannot host, so the ledger test covers
them.
