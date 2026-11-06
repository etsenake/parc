# Browser import ownership

The application menu wraps `BrowserImportViewController` in its native
`BrowserImportWindow`; first launch embeds the same presenter in the existing
setup window. Its original window, Space and Profile remain the invocation owner
even if another window or Space becomes active. The menu's explicit destination
step chooses an actual existing Profile or creates a named new one, with no
initial selection. First launch already owns its destination: its explicit Import
action admits the selected source into that captured Profile, preserving existing
cookies and creating no extra Profile or Space. Discovery and selection do not
submit data. Replay onboarding
does not import into the real session; direct import remains available after
replay. The existing explicit HTML file import remains available.

Discovery first lists installed source applications. Only selecting a source and
continuing asks the native service for its immutable profile descriptors. The
chooser displays each profile's actual supported categories and access
restrictions. The parent wizard selects exactly one original source profile;
selecting a different row replaces that selection, and clicking the selected row
does not deselect it. Extension choices are keyed by both source profile and
extension ID; selecting one profile's extension does not select the same
extension in another profile. Native installation still requires its actual
permission and policy checks.

`BrowserImportCoordinator` submits that original source profile only after a
valid destination is chosen. The New Profile radio reveals a persistent native
name field; a blank trimmed name cannot submit. Radio selection, field edits and
cancellation do not create any Profile. At Import, a new destination is saved as
a distinct Profile and Space before the native context is acquired, with no
browser page or hidden browser window. Existing destinations retain their actual
Profile ID and context; an unused Profile receives only a sidebar Space when
Import is pressed. Existing targets capture their Space and refuse reassignment
or retirement instead of falling back to another active window.

Replace existing cookies starts off. New Profile forces it on and disables the
checkbox; changing back to an existing Profile preserves its value and makes it
editable. Re-entering the destination stage resets replacement to whether New
is selected. The actual native importer receives `skipExistingCookies` as the
inverse of replacement; this choice does not exclude all cookies. Destination
publications retain the original field editor, marked text and selection. Native
Return/Escape stay with an active composition before window submission/cancel.
 The original menu or setup
window owns native authorization sheets. Closing its owner cancels the import;
Close commands from an attached permission sheet never reach a browser behind
it. Native completion is asynchronous and once for an accepted session. An
immediate nil session is admission refusal and has no completion.

Every continuation checks the original owner and generation. Loss of either the
original or active destination cancels pending work. Stop requests cancellation
and waits for the genuine native result. Already committed native category data
is retained and reported; cancellation is not represented as rollback. A failed or
cancelled native result retains any returned bookmark results for selection. Retrying a
failed bookmark save does not rerun native imports or install extensions again.

First-launch setup accepts returned bookmarks before offering optional Safari
password import. An empty result omits the bookmark screen. Accepted/discarded
result pages cannot reopen after passwords; the original Profile/Space remains
the destination throughout. A Stop request or cancelled result preserves returned
bookmarks but suppresses another optional import step. The separate menu wizard
retains its password-then-bookmark sequence. [Setup evidence](onboarding.md#import-progression-inside-setup)
records the recovered conditional ordering and remaining presentation work.

## Sidebar bookmarks

The native service returns immutable source nodes instead of writing a second
bookmark UI. Stable source IDs preserve duplicate names and URLs. Folder
selection applies to its subtree; expansion is independent. A selected child
retains its original ancestor chain. Native trees and selected trees are bounded
to 50,000 nodes and 128 levels before insertion.

`BrowserImportDestination` prepares the selected hierarchy for the exact captured
Space/Profile, preserving mixed folder/page order. New local UUIDs keep imported
items distinct from existing items. The store atomically saves before publishing
the change and restores its previous state if persistence fails. Existing public
bookmark models or application progress messages.

First-launch selection uses the [recovered inline bookmark list](onboarding.md#inline-bookmark-selection).
Select All is scoped to each immutable source result; selection and expansion
remain separate. Retained actions carry a result UUID and recheck its original
window/owner/destination before changing the tree. The menu presenter retains
its existing separate wizard. These presentation changes use the same genuine
import result and atomic insertion path.

During first launch, imported native data and accepted bookmarks are durable
before setup completes. Later completion retains that data and commits only the
remaining draft choices and completion marker. Closing setup leaves those
explicitly imported records intact. Replay retains its existing in-memory-only
draft behavior and disables direct native import.

## Reference and adaptations

discovery, supplied context and asynchronous original-client ownership. The
`0x6818880` owns the custom external-process importer and writer. These artifacts
are analysis references only; Parc does not load their executable code.

and original IDs when a destination is created. REA
`ev_545b7037f7744449e0d2818cda5bfe55021e9e814fe8b8091bfb6ab7d6d508fc`
has an unresolved indirect jump table, attributed separately with original
`ev_54dae23c51bc5dc63852578a0c88d240586516b3623e20336bef20ae7e5386d7`,
applies the selected value through the original subtree and separately toggles
folder expansion. Metadata corroborates original node IDs, parent/index,
children, selected and expanded fields. Recovered pseudocode is not source code.

The installed 1.170 source chooser was observed at 580 × 454 points, with a navy
background, left heading, source icons/radio rows and bottom navigation. Chrome's
category description is not used as evidence of Safari or Firefox capabilities.
No import or permission action was executed in that appearance inspection.

`ev_13e4a7798b352ad6a2740df431f8b0548e2f2469b77e9d78f26d92b29c7255c2`
and `ev_4533cc4315a3c29012c319de73fd01d77ebb4df5cbae505476b57e1495519ed3`
are corroborated by the original assembly and field metadata.

The installed 1.170 destination chooser is 580 × 335 points for its one existing
Profile: no initial selection, existing and New Profile radio rows, an empty
Personal placeholder, the replacement checkbox/help and disabled Import until
valid. Selecting New and then existing established the cookie behavior above;
Close canceled without importing or creating a Profile. Parc uses that layout
with its own branding and actual custom Profile names. Native scrolling for
larger Profile lists, native control focus/pressed styling and error layout are
adaptations; exact large-list, hover, animation and haptic behavior is not claimed.

Defaulting to the first readable source profile, the separate source-profile/
capabilities page, initially selected bookmarks, captured-theme inheritance,
and applying the same parent choice to first launch are explicit Parc policies.
For bookmarks, the invoking Profile keeps its invocation Space; another existing
Profile captures its first actual Space, while an unused one gets a Space at
The retained parent Back action returns profileSelection directly to the source
browser screen; the installed destination exposed only Close and Import, so Parc
does not invent a destination Back control. Source-specific access/password
and restart paths retain their separate owners. Native reader, writer and
capability details belong in `Engine/ParcImport/README.md`.


## Safari access and restart ownership

The actual discovered application's bundle identifier attributes Safari password
export. A restricted profile result — including Chrome, whose user-data
directory is blocked until Full Disk Access is granted — opens that access
guidance before the destination chooser. Chrome closed or running is not the
gate; unreadable files are. The view explains Full Disk Access, opens the genuine macOS Privacy
panel on request and reveals the running Parc bundle in Finder; it never grants
access or interprets a Settings launch as permission success. The menu's original
790 × 630 navy composition and separate Continue/Restart controls use Parc
branding. The right panel uses the installed System Settings icon and actual
First launch uses [the same setup card](onboarding.md#safari-access-inside-setup)
throughout this stage: a passive Parc Settings illustration on the right,
real Settings/Finder/restart actions on the left, and the shared Next button
connected to the existing fresh-readability continuation. The menu's separate
navy window is not embedded in first launch.

The original-window coordinator asks the native discovery owner for a fresh
Safari profile result every second while the guidance view is visible and the
app is active, and on application activation. Only one request can be pending.
Restart becomes available only when the successful aggregate result and an
actual History-capable profile both report complete access. This reports source
readability, not a separately inferred global TCC grant. Continue without
restarting joins a fresh result and proceeds to the actual readable profile
choices; an empty/error result remains visible and cannot begin an import.
Neither readiness nor Continue submits data or creates a destination.

Restart passes `BrowserImportRestartIntent` with the original destination and
onboarding flag to the application restart owner. That owner retains normal
shutdown/cancellation and persistent resumption. The import disables duplicate
Restart while the request is owned; refusal restores the same screen and its
error survives subsequent polls. Closing the import revokes polling and late
callbacks. Resumption discards old discovery objects, rediscovers installed
Safari and obtains new profile descriptors, stopping before destination choice
and user-approved import. Missing Safari returns to the real source chooser.

before profile selection. Its separate Continue action goes to historical
Safari Keychain guidance. Parc presents the separate exported-file owner described
below; direct Safari History discovery still does not expose credentials.
Continue a constant true `isEnabled`, while Restart receives that original
`ImportFeature.State.hasFullDiskAccess` Boolean. REA
`ev_a3f75557d98c6831f82353fde7dba2e044e37ac67138d2c1c2762b5b3d053c0b`
and the typed key-path/field assembly establish the distinct gates. REA
`ev_2433e2704d3982280971f1c7ad068fc77ee319be66242a6c16b9cd99c12b92a4`
and the original assembly establish these owners; they do not justify copying
its fallback probes of unrelated protected files. Selected-source native
readability, single-flight refresh, active-view lifetime and native focus/error
presentation are explicit Parc adaptations. Exact transition motion, complete
keyboard/AX comparison remain distinct from the exported-file implementation.


### Process restart and durable resumption

The application registers its bundled `ParcRestart` helper against the exact
current process before ordinary Quit. The helper confirms its kernel process
watch through a readiness pipe. The application saves browser state and a small
atomic import intent, then arms the helper and uses the existing Notes, quit
warning and native beforeunload owners. Declined shutdown or a closed import
revokes the helper and removes the intent. Accepted shutdown closes the original
import only after consent; the helper waits for that process to exit before
opening the same app bundle with its original optional Parc profile directory.
The intent contains only durable destination Space/Profile identities and the
onboarding flag, never native discovery tokens or imported credentials.

The next actual engine-ready launch consumes the intent once. Resumption waits
for the corresponding onboarding or regular browser owner; expired destinations
or changed setup state cannot redirect it to a different Profile. Safari is
rediscovered through the normal native source owner before any import choice.

`arc_restart_helper.sh` (REA
`ev_86242ccd2eb91d1db3ca309e485187bf294aea309ec98d2ca7d35e2e303a0750`)
establish an external waiter registered before normal application termination, with a five-minute deadline and explicit revocation.
with an exact-PID kernel event and a private command pipe. Its `open -n -a`
launch keeps the selected profile's startup arguments with a fresh process;
normal Chromium profile exclusivity remains authoritative. This is an explicit
platform adaptation. The helper is independently compiled, dependency-audited
and signed inside the app through the normal packager.

The actual helper fixture checks parent-exit, cancellation and invalid-request
behavior while replacing only its final platform launch with a recording seam;
it does not launch Parc. File-backed intent checks cover missing, saved,
consumed, cancelled and corrupt state. Actual macOS permission changes and
end-to-end app restart have not been exercised under the current no-browser-test
direction.

## Exported Safari passwords

Safari import offers a separate exported-password file stage after the selected
source's actual completion and before bookmark selection. Its capability page
also offers an explicit password-file-only route when direct source data is
unavailable. In the application-menu wizard both routes first choose an existing or named new durable Profile;
the file-only route omits the unrelated cookie control. This stage placement is

In first launch the already captured Space/Profile is the destination; the
separate existing/new destination choice belongs to the application-menu wizard.
Its source/profile choices remain inline while native discovery resolves. See
[onboarding import composition](onboarding.md#inline-source-profiles) for the
reference, callback lifetime and explicit local presentation adaptations.

The user exports through Apple's Passwords app (or Safari's password settings on
older macOS), then explicitly chooses or drops one CSV. Help uses Apple's
[documented export flow](https://support.apple.com/en-gb/guide/passwords/mchl35b12625/mac).
Parc does not unlock those applications, read their credential stores directly,
or import passkeys and verification codes. The original import window and exact
destination remain authoritative throughout file selection, native completion,
retry, Stop and Continue/Skip. Source export cancellation accesses no file.

The dedicated native session invokes Chromium's actual sandbox CSV parser and
the destination's actual Profile password store. Only aggregate counts and errors
reach Swift. It refuses OTR, lost owners, unavailable storage and disabled
password-saving policy. Direct and CSV imports share one admission reservation
per destination. Existing realm/username snapshot entries are skipped, duplicate
incoming keys keep the first, and differing values/notes yield a partial result.
This snapshot policy does not claim atomic conflict exclusion against unrelated
concurrent password edits. Accepted writes are read back before reporting saved
counts; Stop retains confirmed writes and waits for the actual result.

A fully confirmed result with no invalid or conflicting rows may offer separate
file-removal consent after 600 ms. Nothing removes the file automatically. The
native lease rechecks original window/Profile and the file's device, inode, size,
modification time and content hash before using macOS Move to Trash. Changed
files and expired owners are refused; a failure leaves an actionable result.
Trash is recoverable and is not secure erasure. Continue/close revokes this
permission without deleting the source. Filesystem identity verification is
immediately before the OS operation, not an atomic filesystem CAS guarantee.

`importPasswords:` selector with the file path. Its upload state is optimistic;
Parc deliberately waits for genuine persistence. The reducer's 600 ms
consent. REA records `ev_d737400ff8c912da9f89403977efdab1a686bfa17f45f6d42e67970cf313f717`,
`ev_0f995cbc11a20dbe73f7ab83d0792e93f714a9d48e9d3e577069ed3a198b681b` and
`ev_1b90e5acd0e7616bbfebfe3aac31c96d1f5e62506a54a2a25cad1fa331c88c3d`
are corroborated by original assembly and conformance metadata.

The installed 1.170 Continue-without-restarting appearance went directly to its
580 × 335 destination chooser; no Import or password action was executed. The
current password screen's geometry was therefore not observed. Parc's native
580 × 630 controls, file-only entry, aggregate results, bounds, conflict policy
and recoverable Trash are explicit adaptations. The full original entryPoint
policy, exact password-screen animation, haptics and help presentation are not
inferred from the shipped child reducer.


First-launch Safari password import now remains in the shared setup card, using
the original 460×200 click-or-drop composition described in
[onboarding](onboarding.md#password-import-inside-setup). Menu import keeps its
existing dedicated window. The presentation change retains the actual native
CSV session, destination lease, stop/result behavior and separate removal consent;
partial/error outcomes never display success. The removed auxiliary onboarding
container has no remaining caller.


## Setup-only iCloud Passwords choice

On macOS14+, first-launch Safari import offers the attributed recommended Apple
extension or manual CSV choice after bookmark acceptance. This is separate from
the menu import sequence. Selection records pending intent; Next accepts it for
the original destination, and successful setup completion submits the fixed
extension through the genuine native Profile installer. Replay and cancellation
cannot submit it. The manual branch retains the existing file reader, password
store admission and file-removal consent. [Onboarding evidence and native
ownership](onboarding.md#safari-password-choice-and-finish-owned-installation)
records the REA chain, implementation adaptations and pending engine rebuild.


### Setup bookmark recommendations

Setup initially selects up to five bookmarks matching the source profile's
actual history, ranked by visit count. Empty/unavailable history leaves explicit
selection to the user; the menu importer's selection policy is unchanged.
The native result carries only that source snapshot's visit counts alongside
its bookmark tree. Matching normalization does not alter saved or navigated
URLs. Duplicate history rows are not summed, and selection keeps original
bookmark IDs, hierarchy and the captured destination. See the
[onboarding reference and adaptations](onboarding.md#import-content-and-initial-bookmark-recommendations).
