# Native direct browser import

The app's chooser calls a two-stage native API. `availableImportSources` resolves
installed application descriptors only. Selecting one descriptor permits
`loadImportSourceProfiles` to read that browser's profile metadata and return
immutable concrete profile tokens, supported categories and access restrictions.
No credentials or cookie values cross into Swift. See `docs/browser-import.md`
for the application-owned chooser, first-launch and bookmark-selection flow.

An accepted import retains its original source token, source directory identity,
regular destination Profile/context and supplied native window. The destination
context is acquired asynchronously, including before the first browser window
exists. A second import into that exact target is refused. A nil session means
immediate refusal with no completion; an accepted session completes once,
asynchronously on main, including early cancellation. Closing its window or
destroying the target Profile cancels further work.

The source app may stay open. Its bundle and original directory device/inode are
checked before reading and writing each category. Live Chromium and Firefox
locks are not a refusal. macOS Full Disk Access is required to read another
browser’s files, including Chrome; a restricted result opens that guidance for
any source. Read-only source database/WAL copies retry when the live browser
writes during the copy. SQLite opens the private temporary copy only after the
source files are unchanged through that copy; a still-changing pair is refused
with a source-changed error rather than importing a torn snapshot. The owned
copy is writable so a copied WAL can recover without creating a source SHM. The
helper initializes Chromium's bundled SQLite through the actual `//sql` owner;
that build omits SQLite autoinitialization.

## Reader and writer boundary

A typed Mojo service runs in a separate utility process with the same explicit
unsandboxed source-file access class as Chromium's profile importer. It receives
only the selected profile, requested category, selected extension IDs and, when
needed, the derived source decryption key. It never discovers other profiles,
performs network requests or writes the destination. Source keys are discarded
on completion/cancellation. Categories are read sequentially and revalidated
before their native writes.

| Source | Directly supported data | Deliberate restriction |
| --- | --- | --- |
| Chrome, Chromium, Brave, Edge, Vivaldi, Opera | History; ordered bookmarks/empty folders; cookies; saved passwords; form entries, current and historical local addresses, local payment cards; explicitly selected Web Store extensions | Actual macOS `v10` AES-CBC formats only. Unknown encryption, absent authorization or invalid encrypted-cookie host binding refuses that category. A source's concrete readable files determine availability. |
| Safari | Default-store history and XML/binary-plist bookmarks | The recovered entry has no direct password/cookie/payment/extension reader. Modern separate Safari profile stores are not advertised. Passwords require an explicit OS/source export. |
| Firefox | History, bookmark hierarchy and form entries | Pinned macOS excludes the external NSS reader; no direct Firefox passwords, cookies, encrypted payment records or add-on installation is advertised. |

Chrome-family source keys come from the browser's actual macOS Keychain service
and account after that source is selected and an encrypted category requested.
The native query preserves macOS authorization; it does not create a replacement
key, fall back to Parc's key or bypass a denial. A pending OS authorization is
owned by macOS: cancelling import stops subsequent native work and drops its
result but cannot dismiss the system's authorization interface. Component checks
never call Keychain or discover/read personal profiles.

The target writes use the original regular Profile's genuine services:

- History schedules `HistoryBackend::ImportPagesWithDetails` on the actual
  history sequence. It commits earlier pending history work before admitting its
  own transaction, retains Chromium's expiration policy and source enum, and
  reports imported/skipped rows only after the real outer commit. A write error
  or observed cancellation rolls back that import batch and restores backend
  transaction ownership; notifications follow commit. Safari/Firefox retain
  their source enum; Chromium-family rows use the pinned OS-migration source
  enum as an explicit adaptation.
- Passwords use the Profile's password store and then verify the exact requested
  credential keys/values in its stored results. The generic store initialization
  error is not treated as an operation result. Invalid blocked-credential
  invariants refuse before calling the store. Confirmed records and unconfirmed
  accepted writes are distinguished; target encryption remains under Parc's
  normal service and Keychain ownership.
- Cookies use an owned clone of the actual CookieManager, original partition
  identity/source metadata and asynchronous admission/write/flush results.
  Skip-existing compares real `CanonicalCookie::UniqueKey` values. A dropped
  connection terminates with confirmed counts and an explicit unconfirmed
  last-write/flush result. Unsupported or rejected cookies are reported.
- Form/address/payment data use real Autofill tables and
  `WebDatabase::RunAtomicImport` on their owned DB sequence. Earlier legacy
  transaction work commits first; the import owns a separate checked outer
  transaction and restores the backend's legacy or scoped transaction mode.
  Cancellation/write failure rolls back only that import. Native change
  notifications follow actual commit, respecting target address/payment
  preferences and policy.
- Extension IDs are intersected with the original explicit selection. Empty IDs
  install nothing. Already installed IDs are left alone; new IDs use the actual
  Web Store install/policy pipeline and original-window permission prompt.
  Supervised approval is not replaced by a generic import acceptance.
- Bookmarks return an immutable ordered tree with stable source identifiers for
  the shell's actual outline selection and atomic sidebar insertion. They are
  not also inserted into a second Chromium bookmark surface.

Cancellation stops pending reads and additional writes; it does not roll back
records already accepted by native services. A writer already in flight is
allowed to drain its real result before session completion, including a utility
process failure or deadline. Cancelling before extension consent aborts the
prompt/fetch; cancelling after genuine acceptance waits for that authorized
installation's result and starts no further IDs. Actual Profile destruction
reports confirmed counts and explicitly unconfirmed pending work, since its
services may drop callbacks during teardown. It never claims those writes were
rolled back. Category failures,
partial writes, warnings and cancellation are distinct outcomes. A five-minute
category deadline stops new work and reports retained completed data. This is
not an all-categories database transaction. Original source timestamps and
available fields are retained where the target model supports them; destination
address/card GUIDs are fresh local identities.


1.122 Core image (`97df76204405d2046261e9f8efeb0cb84f74bf9c223b81f3567e6087b52967a8`).
source and delegate. REA
`ev_f370b5691631073f32cc11408d7088c9228af7b84fb2ba5dc49f2ca068b70460`.

Core `0x68c382c` → `0x6827c44` → `0x67e53f0` → `0x6818880` retains one
context-owned import, intersects categories with source support, snapshots the
source and installs its own host/writer. REA
`ev_a4ce74d1fcf31ba8c239408d8608154223d3fc77cbc6f3a3233d29902fde5db4`,
`ev_7e9fa12b02268f8643ee93ca30833e0d234211ebdd44488b1628e87b4afa16bd`,
`ev_1a7bfecdf7f50f717950b3d40519a0ecefa5f184c6ec9afc83da6399b8c78b05`.
The shipped paths identify `arc/browser/importer/importer_manager.cc`,
`arc_external_process_importer_host.cc` and the Chrome reader. Bounded original
assembly establishes base host `0x5ff1698`/start `0x5ff17a4`, writer `0x5ff50b8`,
source Chrome DB/decrypt work around `0x67af000`–`0x67b1800`, encrypted-cookie
32-byte host validation `0x67b03fc`–`0x67b049c` and source extension preference
filters around `0x681689c`. These excerpts are not claimed as a complete original
class reconstruction.

Safari's actual `0xa8243b0` entry and `0xa824bb0` history reader support only the
history/bookmark categories claimed here; fresh REA
`ev_02e22e14d5d9eafeca75026b9f62b78163ae32a0df4f79fb8ce293de12f1ff71`.
Firefox follows the retained importer schema and current pinned macOS constraints.
The typed utility protocol, explicit per-category failures, cancellation deadline,
source identity checks and shell-owned bookmark commit are Parc adaptations of
those recovered owners. Compilation and disposable native fixtures establish

## Focused checks

`tests/BrowserImport/run_chromium.py` compiles the actual Chrome reader and snapshot
helper with the pinned utility target flags and existing Chromium component
libraries, then runs only temporary SQLite/JSON/encryption fixtures.
`tests/BrowserImport/run_readers.py` does the same for Safari/Firefox XML/binary
plists, history/bookmarks/forms, WAL, invalid schemas, path/cancel and original
file preservation. `tests/BrowserImport/run_writers.py` compiles the actual modified HistoryBackend
and WebDatabase sources, links the pinned component libraries and checks commit,
rollback, cancellation, expiry, failure and reopened durability in disposable
databases under both legacy and scoped transaction modes. All runners require
explicit source/output paths and a private output directory; none generates GN,
builds the engine, opens a browser, imports real profiles or accesses Keychain.
Native service/writer/session integration is checked separately against the exact
pinned targets and generated Mojo headers. Cookie/password service outcomes and
extension consent/install remain source/compiler checked; the isolated database
fixtures do not establish those live Profile behaviors.

## Explicit exported password CSV

`native_password_file_import.mm` owns a separately selected file and original
regular destination Profile/window. It shares destination admission with the
ordinary importer, retains the actual CEF context, and rejects OTR, shutdown and
password-saving policy refusal. It never uses the Safari History reader for
credentials. Chromium's `LaunchCSVPasswordParser()` service parses the file in
its genuine utility process; ProfilePasswordStore receives actual imported
credentials, original URL/realm, username, password and note. Credentials never
cross the Swift bridge or enter progress messages.

Admission reads a nonempty regular nonsymlink file at most 1000 KiB and verifies
its identity before/after reading. Parsing has a 30-second pre-write deadline
and a 3000-row limit, consistent with the upstream import bounds. Only valid
HTTP(S) credentials within upstream URL/username/password/note lengths are
admitted. Existing realm/username snapshot entries and blocked realms are
skipped; duplicate incoming keys keep the first. Conflicting values or notes
remain partial outcomes. This is a snapshot policy, not an atomic
compare-and-insert guarantee against other password-manager edits.

Actual AddLogins completion is followed by store readback matching expected
key/password/note. Only confirmed rows count as imported. Accepted writes drain
after cancellation, and Profile teardown distinguishes unconfirmed writes from
rollback. A fully confirmed result retains only file identity and the original
owner for optional explicit removal consent. Native removal re-reads and checks
device/inode/size/mtime/SHA-256, then uses recoverable macOS Trash; no automatic or
secure deletion is claimed. The OS path operation follows the identity check,
without claiming an atomic filesystem CAS. Closing the lease revokes removal.

The synthetic file component exercises actual admission/hash helpers, and the
coordinator fixture exercises original destination, cancellation, stale results
and explicit removal dispatch. They do not execute a real Profile password store
or read personal credentials; live native service behavior remains distinct from
in `docs/browser-import.md`.
