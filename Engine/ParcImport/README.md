# Native direct browser import

The app's chooser calls a two-stage native API. `availableImportSources` lists
browsers with importable or access-restricted data. Selecting one descriptor lets
`loadImportSourceProfiles` read that browser's profile metadata and return
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
locks are not a refusal. If macOS restricts source files, including Chrome's,
a restricted result opens Full Disk Access guidance for that source. Read-only
source database/WAL copies retry when the live browser writes during the copy. SQLite opens the private temporary copy only after the
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
before their native writes. Returned timestamps are microseconds since
1601-01-01 UTC, address fields are keyed by Chromium's numeric field types, and
the key is always the source browser's own, never Parc's.

| Source | Directly supported data | Deliberate restriction |
| --- | --- | --- |
| Chrome (including Beta, Dev and Canary), Chromium, Brave, Edge, Vivaldi, Opera, Opera GX, Arc, Dia, Comet, Helium | History; ordered bookmarks/empty folders from the local and account stores, plain or encrypted; cookies; saved passwords, including those saved to the browser account; form entries, current and historical local addresses, local payment cards; explicitly selected Web Store extensions | Actual macOS `v10` AES-CBC formats only, including Chromium's fallback key (below). Unknown encryption, absent authorization or invalid encrypted-cookie host binding refuses that category. A source's concrete readable files determine availability. |
| ChatGPT Atlas | History; ordered bookmarks/empty folders; explicitly selected Web Store extensions | Its encryption key sits where other apps cannot read it, so cookies, passwords and form/address/card data are not offered and the Keychain is never queried; an encrypted-only bookmark store cannot be read. |
| Safari | Default-store history and XML/binary-plist bookmarks; each Profile's history and the payment cards from Safari's export file | This reader supports no direct password/cookie/payment/extension import; payment cards come only from the export file. Separate Safari Profile stores are not read directly. Passwords require an explicit OS/source export. |
| Firefox, Zen | History, bookmark hierarchy and form entries | Pinned macOS excludes the external NSS reader; no direct passwords, cookies, encrypted payment records or add-on installation is advertised. Passwords come from the browser's own CSV export (below). |

Safari's export file reaches this reader as one private folder per Safari
Profile, written by the app's ZIP reader, holding that Profile's exported
`History.json`. When a folder has no `History.db`, the Safari reader reads that
JSON instead: it requires `metadata.data_type` to be `history`, takes `url`,
optional `title`, `time_usec` (Unix microseconds) and the visit count from
`visit_count` or Apple's documented `visits_count`, hides redirect sources
(entries with a `destination_url`), and skips invalid entries with one warning.
The file is limited to 256 MiB and checked for change while it is read.
The export's payment cards arrive as `PaymentCards.json` in the default
Profile's folder, or in a folder of their own when the export has no history,
and discovery then offers the autofill category for that folder. The reader
requires `metadata.data_type` to be `payment_cards` and takes Apple's
documented keys: `card_number` with spaces and dashes removed,
`cardholder_name`, `card_name` as the nickname, and `card_expiration_month`
(1–12) and `card_expiration_year` (four digits) when plausible. Entries without
a number are skipped with one warning. The file is limited to 16 MiB and
checked for change while it is read; the raw bytes are zeroed once parsed, and
every parsed number and name is zeroed before the reader returns, as the
Chromium reader zeroes a decrypted card number.
`loadSafariExportProfiles` turns those folders into ordinary Safari-family
profiles, so session, writer, cancellation and destination policy are the same
as direct imports. Reading separate Safari Profile folders inside Safari's
private container is decided against: that layout is undocumented and has
already moved once, it still needs Full Disk Access and a private Safari
database for Profile names, and Safari's export file covers the same need in a
format Apple documents.

Zen is built on Firefox and uses the Firefox reader, which names the source
browser in its messages, so a damaged Zen profile is reported as Zen's. Zen's
own build sets its profile name to `zen`, so its `profiles.ini` and profiles
live in `~/Library/Application Support/zen`; its bundle identifier is
`app.zen-browser.zen`. Reading Firefox's encrypted password store
(`logins.json` with `key4.db`) directly is decided against: it would rebuild
Firefox's key handling for its older and its Firefox 144 formats, need a
primary-password prompt, and chase future format changes, while the CSV export
step covers the same people.

Each Chromium-family source's data folder, bundle identifier and Keychain item
come from the browser's own source or build files where they are public, and
otherwise from importers in other shipping browsers that read the same files.
Chrome's Beta, Dev and Canary folders and bundle identifiers are Chromium's own:
its user-data-directory guide and code-signing requirement name them, and its
Keychain code picks `Chrome Safe Storage`/`Chrome` by branding alone, so every
channel shares it. Helium's patches set its folder to `net.imput.helium` and
its item to `Helium Storage Key`/`Helium`. Dia (`Dia/User Data`,
`Dia Safe Storage`/`Dia`) matches the importers Zen and Helium ship; Comet's
folder (`Comet`) matches Helium's importer and its item
(`Comet Safe Storage`/`Comet`) matches tools tested on real installs. Opera and
Opera GX keep their first profile in the data folder itself (or its `Default`
folder) and each further profile, which Opera calls a side profile, in a folder
of its own under `_side_profiles`, as Opera's forum volunteers and the importers
and forensic tools that read them describe. Discovery lists the side profiles
after the browser's own, in folder order, each read from its folder's `Default`
when that holds `Preferences`, otherwise from the folder itself. It takes the
`name` from the folder's `<folder>_sideprofile.json` settings file, or numbers
the browser's name by the profile's place in the list (`Opera GX 3`) when there
is none. A side profile whose settings list `side-profile-clear-on-exit` is one
Opera wipes when it quits, so it is not offered. Side profiles run from the
same app, so they share its Keychain item and the import's single key request.
Importers disagree on Opera GX's Keychain item, so Parc asks for
`Opera GX Safe Storage`/`Opera GX` and, only when that item does not exist, `Opera Safe Storage`/`Opera`; a wrong key almost
always fails the reader's padding check, and that category is then refused. ChatGPT Atlas keeps its
profiles in `com.openai.atlas/browser-data/host`, as OpenAI's own tooling reads
them, and its key in an OpenAI-only Keychain group; its `login-staging-` profile
is the app's sign-in scratch space and is not offered.

Chrome-family source keys come from the browser's actual macOS Keychain service
and account after that source is selected and an encrypted category requested,
or bookmarks whose current copy is encrypted (below). The native query preserves
macOS authorization; it does not create a replacement key, fall back to Parc's
key or bypass a denial. Loading a source's profiles, which happens each time
it is chosen, gives them one shared key slot, so an import asks at most once
per browser. Sessions that need the key while its request is pending, such as
the background sessions that start together for several profiles, wait for
that one request instead of raising their own prompts. The key, or a refusal,
then serves every profile and category of that import, so a declined prompt is
not repeated; choosing the source again asks afresh. A pending OS authorization
is owned by macOS: cancelling import stops subsequent native work and drops its
result but cannot dismiss the system's authorization interface. Component
checks never call Keychain or discover/read personal profiles.

Decryption matches Chromium's: AES-128-CBC with an IV of sixteen spaces and a
strict PKCS#7 padding check, so a wrong key almost always fails instead of
yielding garbage.
When the browser's key fails on a `v10` value, the reader retries with the
fixed key Chromium's decryptor falls back to, derived from an empty password
(PBKDF2-HMAC-SHA1, one iteration, salt `saltysalt`), for rare values written
without a usable key. As in Chromium, this covers bookmarks, passwords, cookies
and cards alike, and only after the browser's own key was obtained; without
that key nothing is decrypted.

### Chromium-family bookmark stores and account passwords

Chromium keeps device bookmarks in `Bookmarks` and Google Account bookmarks in
`AccountBookmarks`. While it rolls out bookmark encryption it also writes
`EncryptedBookmarks2` and `EncryptedAccountBookmarks2`: the same JSON as one
macOS `v10` AES-CBC value. Its final stage writes only the encrypted copy and
deletes the plain one after a successful load; browsers built on Chromium inherit
the same files. Discovery offers Bookmarks when any of the four exists.

For each store the reader uses the plain copy unless the encrypted copy is the
only one or was saved more than a minute after it; Chromium writes the two back
to back while it keeps both, so a plain copy that is current never needs the
key. The session asks the Keychain for a bookmarks-only import only when some
store's current copy is encrypted. A refused key or failed decryption falls back
to an existing plain copy with a warning. Account items come first, as in
Chromium's bookmarks bar; a same-named folder in the same place combines with
its twin, and a bookmark with the same title and address in both stores appears
once, while duplicates inside one store are kept. A store that cannot be read
adds a warning and the other is still imported; the category fails only when no
store can be read.

`Login Data` keeps its all-or-nothing rule: one undecryptable saved password
refuses the category. `Login Data For Account` is read separately; any problem
there adds a warning and drops only that file, unless it is the only password
file. Discovery offers Passwords when either exists. A login in both files is
imported once, keeping the copy whose password changed most recently (the
account copy on a tie). The password store replaces a saved login with the same
site, address, username and field names instead of adding a second one, so a
repeated import updates rather than duplicates.

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
  preferences and policy. A card whose number fails Chromium's own card-number
  check is skipped with a warning instead of failing the category, and a card
  whose digits and expiry match a locally saved card, or an earlier card in the
  same import, is skipped, so a repeated import does not duplicate cards while
  a reissued card with a new expiry still arrives.
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
partial writes, warnings and cancellation are distinct outcomes; a warning about
skipped records leaves its category complete, and only a failed category makes
the import partial. History visit counts returned with an import that also
asked for bookmarks keep the largest count per address, because Safari and
Firefox report one row per visit carrying the same total. A five-minute
category deadline stops new work and reports retained completed data. This is
not an all-categories database transaction. Original source timestamps and
available fields are retained where the target model supports them; destination
address/card GUIDs are fresh local identities.

## Ownership and verification

An import belongs to one exact destination context. Supported categories are
intersected with the source's capabilities before reading. The utility protocol,
per-category failures, cancellation deadline, source-identity validation and
shell-owned bookmark commit are Parc's implementation contracts.

This path has no third-party executable or library dependency beyond the pinned
engine.

## Focused checks

`tests/BrowserImport/run_chromium.py` compiles the actual Chrome reader and snapshot
helper with the pinned utility target flags and existing Chromium component
libraries, then runs only temporary SQLite/JSON/encryption fixtures, including
made-up encrypted, account and merged bookmark stores, an account password
file encrypted with a test key, and bookmarks, passwords, cookies and a card
saved with Chromium's fallback key. Its component libraries must come from the
pinned Chromium; output built from another milestone is not a valid input.
`tests/BrowserImport/run_readers.py` does the same for Safari/Firefox XML/binary
plists, history/bookmarks/forms, WAL, invalid schemas, path/cancel and original
file preservation. `tests/BrowserImport/run_writers.py` compiles the actual modified HistoryBackend
and WebDatabase sources, links the pinned component libraries and checks commit,
rollback, cancellation, expiry, failure and reopened durability in disposable
databases under both legacy and scoped transaction modes. All runners require
explicit source/output paths and a private output directory; none generates GN,
builds the engine, opens a browser, imports real profiles or accesses Keychain.
Native service/writer/session integration checks use the exact pinned targets
and generated Mojo headers. `tests/BrowserImport/check_discovery.py` compiles
discovery and its made-up fixture, `ImportDiscovery.mm`, with the shipping
output's Parc browser flags, syntax only: Opera and Opera GX homes whose side
profiles use either folder layout, a name, no name or clear-on-exit, a browser
whose only data is in a side profile, and a Chrome folder whose stray
`_side_profiles` is ignored.

## Explicit exported password CSV

`native_password_file_import.mm` owns a separately selected file and original
regular destination Profile/window. It shares destination admission with the
ordinary importer, retains the actual Chromium context, and rejects OTR, shutdown and
password-saving policy refusal. It never uses the Safari History reader for
credentials. Chromium's `LaunchCSVPasswordParser()` service parses the file in
its genuine utility process; ProfilePasswordStore receives actual imported
credentials, original URL/realm, username, password and note. Credentials never
cross the Swift bridge or enter progress messages.

Admission reads a nonempty regular nonsymlink file at most 32 MiB and verifies
its identity before/after reading. Chromium's parser service has no size limit
of its own; its upstream importer stops at 1000 KiB and 3000 rows, so Parc
feeds the parser chunks within those bounds instead. The file is cut only at a
line break outside quotes, exactly where Chromium's parser ends a record, and
each chunk repeats the header line, so every row parses as it would in one
piece. Chunks are parsed and saved one at a time, each parse with its own
30-second deadline: memory holds the file, one chunk's rows, a copy of the
saved-password snapshot and the keys awaiting verification, never every parsed
row. A file with no data rows or an unusable header fails before anything is
saved. Only valid HTTP(S) credentials within upstream
URL/username/password/note lengths are admitted. Firefox and Zen exports carry Firefox's own account entry under a
`chrome://` address for anyone signed in to a Mozilla account; Firefox's
Passwords page hides it, and the importer skips it rather than counting an
invalid row. One snapshot of saved passwords, taken before the first write,
serves every chunk: existing realm/username entries and blocked realms are
skipped, and duplicate incoming keys keep the first even across chunks.
Conflicting values or notes remain partial outcomes. This is a snapshot policy, not an atomic
compare-and-insert guarantee against other password-manager edits.

After the last chunk's AddLogins completes, one store readback matches every
expected key/password/note. Only confirmed rows count as imported. Accepted
writes drain after cancellation; Stop, a closed window, a parser failure or
password saving being turned off after earlier chunks were saved starts no
further chunk and verifies what was written, reporting a partial or cancelled
import that never offers to remove the file. Minimising or hiding the window
does not stop it. Profile teardown
distinguishes unconfirmed writes from rollback. A fully confirmed result retains only file identity and the original
owner for optional explicit removal consent. Native removal re-reads and checks
device/inode/size/mtime/SHA-256, then uses recoverable macOS Trash; no automatic or
secure deletion is claimed. The OS path operation follows the identity check,
without claiming an atomic filesystem CAS. Closing the lease revokes removal.

The synthetic file component exercises actual admission/hash helpers and the
chunk splitter, including quoted line breaks and chunk boundaries, and the
coordinator fixture exercises original destination, cancellation, stale results
and explicit removal dispatch. Both use disposable data. Application ownership
and source mapping are described in [browser import](../../docs/browser-import.md).
