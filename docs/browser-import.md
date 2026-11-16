# Browser import ownership

Menu import and first launch share `BrowserImportViewController` and
`BrowserImportCoordinator`. Both keep the invoking physical window, Space and
Profile throughout the operation. Switching another window or Space never
retargets an import. Discovery and source selection alone submit no data.

## Source and destination policy

The source cards discover installed browsers and load immutable profile results
inline. Every readable source profile comes along, including its extensions;
there is no separate profile-selection or destination-choice step. An unreadable
source remains represented so access guidance can follow.

The source Default profile, or first readable profile, imports into the original
Parc Space/Profile. Further profiles reuse an unused eligible Parc Profile with
the same name, case-insensitively, or create a named destination. Each destination
is rechecked before use. Native imports preserve existing cookies
(`skipExistingCookies=true`); the current flow has no cookie-replacement control.

Arc imports also read the source sidebar snapshot to bring Spaces, pinned tabs,
Favorites and automatic-archive settings into the corresponding Parc Profiles.
If that snapshot cannot be read, ordinary browser-data import still uses the
normal destination policy. The explicit HTML bookmark-file import remains.
Native category capabilities and access failures determine what can be imported;
Swift bookmark/progress models never receive native credential contents.
Choosing a Chromium-family browser replaces the intro line with a note that
macOS may ask for that browser's Safe Storage key, which unlocks the bookmarks,
passwords and cookies it keeps encrypted; Safari, Firefox and Zen keep the intro.

## Sequencing and cancellation

Bookmarks are collected first. Other browser data runs in background native
sessions, then extension installation follows using each original destination.
Safari, Firefox and Zen background data wait for the password-file session to
release the Profile. A detached presenter can retain accepted background work;
later imports wait for earlier background work rather than racing the same
owner. Failures are reported as partial or failed, preserving already committed
data.

All callbacks check generation, source lease and original/current destination.
Stop waits for the actual native result. Cancellation is not rollback: confirmed
category data and returned bookmark results survive. Retrying bookmark insertion
does not repeat native import or extension installation. A nil native session
means admission was refused, not that an asynchronous completion will arrive.

First launch accepts bookmark results before the optional Safari, Firefox or
Zen password file; an empty result omits that screen. Menu import retains its
password-then-bookmark order.
Accepted/discarded result pages cannot reappear later. A cancelled import keeps
returned bookmarks but suppresses another optional import stage.

## Sidebar bookmarks

Immutable source IDs preserve duplicate names and URLs. Folder selection affects
its subtree, while expansion is separate. A selected child keeps its ancestor
chain. Native and selected trees are bounded to 50,000 nodes and 128 levels.
Bookmarks initially select all source nodes; the user can change that selection.

`BrowserImportDestination` prepares mixed folder/page order for the captured
Space/Profile with new local UUIDs. The store saves atomically before publication;
failure restores prior state. Imported Chromium internal addresses normalize to
`parc://`; unsupported `arc://` destinations are refused. Result UUIDs and
original window/owner/destination checks invalidate stale bookmark controls.

Explicit native imports and accepted bookmarks are durable before setup finishes.
Replay uses the same real import path: cancelling replay does not undo accepted
imports. Theme/appearance previews remain drafts until Finish. Setup bookmark
recommendations and current inline presentation are described in
[onboarding](onboarding.md).

## Safari access and restart ownership

Restricted source readability opens Full Disk Access guidance, including Chrome
when its files are inaccessible. Running versus closed is not the access test.
User actions open the real privacy panel or reveal the actual Parc bundle; the
app never grants access or treats a Settings launch as success. Setup stays in
its shared card, while menu import uses its own window.

While the access view is active, fresh source discovery runs single-flight every
second and on activation. Restart becomes available only when the aggregate
result and a History-capable profile both report complete readability. Continue
uses a fresh result; it never submits data merely because access changed.
The setup path can continue with readable data or Safari password import even
when Full Disk Access is deferred.

### Process restart and durable resumption

`BrowserImportRestartIntent` retains original destination and setup/replay
provenance. `ParcRestart` registers an exact-PID kernel watch before ordinary
Quit and acknowledges readiness through a private pipe. The app saves state and
an atomic intent before arming the helper; Notes, quit warning and beforeunload
consent still govern termination. Refusal or closing the import revokes the
helper and intent. Accepted shutdown opens the same bundle only after the exact
process exits, preserving explicit profile arguments.

The next engine-ready launch consumes the intent once, waits for the correct
setup/browser owner and rediscovers the source. Expired destinations cannot
redirect to another Profile. Replay additionally restores its pending setup
choices from the replay intent. No discovery token or credential is persisted
in the restart file. A held earlier import delays restart rather than truncating
its background work.

## Exported Safari and Firefox passwords

The user explicitly chooses or drops one exported CSV. Parc does not unlock
Apple's credential applications, read their stores directly, or import passkeys
and verification codes. Firefox and Zen imports offer the same step, with
their own export steps; Chromium's CSV reader takes Firefox's `url`, `username`
and `password` columns and ignores its realm, form, identifier and time columns.
The hidden Mozilla-account entry such exports carry is skipped, not counted as
a failed row.
The original import window and destination govern file selection, completion,
Stop, retry and Continue/Skip.

The native session uses Chromium's sandbox CSV parser and actual Profile
password store. Only aggregate counts/errors reach Swift. OTR, missing owners,
unavailable storage and disabled-saving policy refuse. Direct and CSV imports
share destination admission. Existing realm/username entries are skipped,
incoming duplicates keep the first, and differing values/notes yield a partial
result. Accepted writes are read back before reported saved counts. Stop keeps
confirmed writes. This snapshot policy does not exclude unrelated concurrent
password edits atomically.

A fully confirmed result may offer separate removal consent after 600 ms.
Nothing deletes a source automatically. Before Move to Trash, the lease checks
window/Profile, device, inode, size, modification time and content hash. Changed
files or expired owners refuse; errors remain actionable. Continue/close revokes
permission. Trash is recoverable, not secure erasure; the check immediately
precedes the OS operation but is not an atomic filesystem compare-and-swap.

## Setup-only iCloud Passwords choice

On macOS 14 through 15.4, Safari setup offers the Apple extension or manual CSV
after bookmarks; other versions go straight to manual CSV, for the reason in
[onboarding](onboarding.md#safari-password-choice-and-finish-owned-installation).
Selecting the recommendation records intent; Next accepts it for the original
destination. Successful Finish/browser preparation submits the genuine Profile
installer. Replay supports that same Finish-owned installation; cancelling
before Finish does not install it. Manual import keeps the same native
password-store and file-removal contracts.

## Implementation and validation

Primary owners are `BrowserImportCoordinator.swift`, the original setup/menu
presenter, `BrowserImportDestination` and [native import](../Engine/ParcImport/README.md).
Focused import, access, focus, password-file and restart-helper checks use
fixtures or inert components. Restart fixtures replace final app launch with a
recording seam. Native reader/writer fixtures use disposable databases; see the
[native import checks](../Engine/ParcImport/README.md#focused-checks).

Parc’s utility content client registers the isolated import reader. Its protocol
and reader sources live under Parc’s importer target; atomic history and web-data
writes retain their dedicated Chromium transaction patch.
