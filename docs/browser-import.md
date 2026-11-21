# Browser import ownership

Menu import and first launch share `BrowserImportViewController` and
`BrowserImportCoordinator`. Both keep the invoking physical window, Space and
Profile throughout the operation. Switching another window or Space never
retargets an import. Discovery and source selection alone submit no data.

## Source and destination policy

The source cards discover installed browsers and load immutable profile results
inline. Every readable source profile comes along, including its extensions;
there is no separate profile-selection or destination-choice step. Opera and
Opera GX side profiles count as profiles of their own, each under the name Opera
shows for it, or a numbered one when it has none, except those Opera wipes when
it quits. An unreadable
source remains represented so access guidance can follow.

The source Default profile, or first readable profile, imports into the original
Parc Space/Profile. Further profiles reuse an unused eligible Parc Profile with
the same name, case-insensitively, or create a named destination. Each destination
is rechecked before use. Native imports preserve existing cookies
(`skipExistingCookies=true`); the current flow has no cookie-replacement control.

Arc imports also read the source sidebar snapshot to bring Spaces, pinned tabs,
Favorites and automatic-archive settings into the corresponding Parc Profiles.
If that snapshot cannot be read, ordinary browser-data import still uses the
normal destination policy. Safari's export file is the file-based route
(below).
Native category capabilities and access failures determine what can be imported;
Swift bookmark/progress models never receive native credential contents.
Choosing a Chromium-family browser replaces the intro line with a note that
macOS may ask for that browser's Safe Storage key, which unlocks the bookmarks,
passwords and cookies it keeps encrypted (Helium calls it its Storage Key);
Safari, Firefox, Zen and ChatGPT Atlas, whose key Parc cannot read, keep the
intro.

## Sequencing and cancellation

Bookmarks are collected first. Other browser data runs in background native
sessions, then extension installation follows using each original destination.
Safari, Firefox and Zen background data wait for the password-file session to
release the Profile. A detached presenter can retain accepted background work;
later imports wait for earlier background work rather than racing the same
owner. Failures are reported as partial or failed, preserving already committed
data.

The engine reports each extension it couldn't add with its destination Profile
and the reason when one is known. Each failure reaches the browser window's
[notice](onboarding.md#included-setup-order-and-ad-blocker-branch), queued
behind the import's own “Only some of your data imported” or failed notice when
its data failed too. It names the Profile when the import was adding extensions
to more than one, as in “Couldn’t add Grammarly to Work”, and **Retry** installs
just that extension again from the same source Profile into the same Parc
Profile. An extension whose destination went away before installing has no
Retry, and a policy, parental or safety block says so instead of offering one.
The app reads these reports through its own adapter, so paired with an older
engine that only names the extensions, it shows the plain notice without a
Profile or Retry.

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

## Safari's export file

Safari's **File → Export Browsing Data to File** saves a ZIP file. Apple
documents its contents: one bookmarks web page, one passwords CSV and one
payment-cards JSON, plus a history JSON and an extensions JSON for each Safari
Profile. Names are localized and a Profile's files carry ` - <Profile name>`
after the base name; the default Profile's have no suffix. Parc therefore
recognises JSON files by the `data_type` inside them, not by name.

With Safari's card chosen, **Use Safari’s export file instead…** opens a file
panel for the ZIP, in setup and the File menu import window; setup's Safari
access page points back to it for people who would rather not grant Full Disk
Access. Parc's own reader opens the ZIP on a
background queue (stored and deflated entries, ZIP64, CRC-checked, with size
limits) and writes only what it imports to a private temporary folder.
Bookmarks become the usual bookmark page for the original Space/Profile.
Passwords go through the same native CSV importer into the original Profile,
before any history, and Parc deletes its copy of the CSV as soon as that import
ends. Each Profile's history goes through the native Safari reader and the
history writer: the default Profile's into the original Space/Profile, the
others into a same-named unused Parc Profile or a new one, as with direct
imports. Payment cards go to the original Profile through the native Safari
reader and the same card writer Chromium-family imports use. Parc writes the
cards file only into the default Profile's private folder (a folder of its own
when the export has no history), wipes its in-memory copies, and deletes the
file as soon as the reader has read it, or when that Profile's import ends if
reading never finished. Safari extensions are listed in the file but not
imported. The temporary folder is removed when the import's background work
ends or it is cancelled, and leftovers from an interrupted import are removed
the next time an export is opened. A failed password, history or card part
reports through the import failure notice.

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

When Apple's installed iCloud Passwords helper admits Parc, Safari setup offers
the Apple extension or manual CSV after bookmarks; otherwise it goes straight to
manual CSV, as [onboarding](onboarding.md#safari-password-choice-and-finish-owned-installation)
explains.
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
recording seam. `tests/ParcCoreTests/Data/Import/SafariBrowsingExportTests.swift` runs the export ZIP
and bookmark-file readers against made-up archives, including ZIP64, data
descriptors, damaged and hostile entries, and localized file names.
`EngineFacadeImportTests` feed the extension-report adapter the current
engine's report shapes; `EngineFacadeOldEngineTests` feed the older shapes
without the newer failure class, so the facade fails to link if it names it.
The native integration fixtures below use real Chromium libraries and disposable inputs.

Parc’s utility content client registers the isolated import reader. Its protocol
and reader sources live under Parc’s importer target; atomic history and web-data
writes retain their dedicated Chromium transaction patch.

### Chromium integration fixtures

The four [BrowserImport harnesses](../tests/BrowserImport) belong to the pinned
engine. All three Python runners take the same arguments. Set `repo`, `src`,
`engine_out` and `ninja` to the absolute Parc checkout, matching Chromium
source tree, completed component output and Ninja executable. Use a separate
private output directory for each run.

```sh
python3 tests/BrowserImport/run_chromium.py --parc-root "$repo" \
  --chromium-source "$src" --engine-output "$engine_out" --ninja "$ninja" \
  --output "$results/chromium"
```

| Fixture | Current entry point and coverage |
| --- | --- |
| `ChromiumReaders.cc` | `run_chromium.py` exercises Chromium profile bookmarks, passwords and fallback keys with the actual reader and snapshot code. |
| `SafariFirefoxReaders.mm` | `run_readers.py` exercises plist and SQLite import, including WAL snapshots, against disposable Safari and Firefox inputs. |
| `HistoryWriter.cc` | `run_writers.py` checks commit, rollback and reopened databases through HistoryBackend and WebDatabase in both transaction modes. |
| `ImportDiscovery.mm` | The fixture includes the discovery implementation and constructs synthetic Chrome, Opera and Opera GX homes. It has no checked-in executable target or runner. For its compile check, query the existing `obj/parc/browser/native_import_discovery.o` command with Siso in the matching engine output. Keep the compiler, includes, defines and Objective-C++ flags. Replace the input with this fixture’s absolute path, remove object and dependency outputs, and pass `-fsyntax-only`. This checks compilation only. |

A future GN home would add `tests/BrowserImport/BUILD.gn` and map it and the
four fixtures into `//parc/tests/browser_import` in
`Engine/ParcHost/overlay.json`. Define four separate `testonly` executables,
one per existing `main`. Link the two readers to `//parc/importer:service`,
`//base`, `//url`, `//sql` and `//third_party/sqlite`, and link Foundation
for the Objective-C++ reader. Link the writer to the history and webdata
components, SQL, base and base test support, and run it with and without
`--scoped`. For discovery, use the same browser compile configuration and
link the native import model and reader dependencies. Adjust the fixture’s
implementation include to the overlay location and avoid linking a second
copy of discovery. Preserve the uncaught-exception handler for both
Objective-C++ fixtures. These proposed targets require engine-owner approval.
