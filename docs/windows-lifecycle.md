# Browser window lifecycle

Regular windows retain stable identities, their Space and selected content,
focused panes, sidebar mode/width and activity dates. Each live page has one
window owner even when the same shared sidebar item is selected elsewhere.

`BrowserWindowController.swift` holds the window object's stored state, setup,
AppKit overrides and the engine and AppKit callbacks it answers. Its behavior
lives in `BrowserWindowController+<Topic>.swift` extensions grouped by area
(sidebar, splits, Peek, command bar, downloads and so on), and its page panes
live in `BrowserPane.swift`. Add new window code to the matching topic file.

A background tab that has not been on screen for four hours sleeps through
Chromium's in-place discard, which keeps its history and reloads it when shown;
pages in use by the automatic-archive standard stay awake. Easel pages follow
the same rule through [embedded page retirement](embedded-pages.md#admission-and-lifetime).

## Restoration and launch continuity

AppKit restores regular windows by stable ID and owns frame, minimized and
fullscreen restoration ordering. When AppKit reopens nothing, Parc reopens the
first saved window itself at that window's own frame, fitted to today's screens
([window frames](sidebar-resize.md#window-frames)). Restoration does not bring
every window to the front. If a saved Space no longer exists, that window falls
back to the first available Space without changing another window's selection.

Unrequested or failed restoration records remain available rather than being
discarded. Legacy records have a fallback path. Disabling restoration does not
seed new saved window records. Private and popup windows are never persisted.

Parc respects the per-app `NSQuitAlwaysKeepsWindows` setting.
`LaunchContinuity` records a running marker and executable modification time/size
in `launch.json`: an interrupted run or changed build restores every eligible
window; the ordinary launch path starts with the first requested window. The
running marker is written only after engine startup succeeds. Failed startup
and forwarding a launch to an existing process do not rewrite it.

AppKit's per-bundle restoration list can be shared by launches using different
data roots, so stored shell records still require their own identity checks.
A two-phase readiness gate queues Dock/URL requests until the engine and the
required Profile are ready.

Quit, Dock termination and system termination enter the same application
termination coordinator. It saves window/history state, waits for genuine page
consent and native-service drain, then lets AppKit finish termination.
Chromium's own restart requests, such as System's Restart button in More
Settings, take the same path without the **Quit Parc?** warning; once it
finishes, Chromium relaunches Parc through Parc Helper with the same data. When
a quit stops short (the warning's Cancel, Notes or settings that can't close, a
page that refuses to leave, or a refused onboarding replay close), Parc tells the
engine it is no longer quitting. That drops any pending restart, so the next
Quit only quits.

## Saved sidebar backups and startup rescue

The sidebar, Archive, window records and settings live in `session.json` in
Parc's Application Support folder; visits live beside it in `history.jsonl`.
Saves replace the file atomically, and a file that fails to decode or validate
is never overwritten.

**Backups.** `SessionBackups` keeps earlier good copies in `Sidebar Backups`, an
owner-only folder beside `session.json`. After a save, and once at launch, Parc
writes a copy when the newest one is at least an hour old and the sidebar has
changed, so a busy hour costs one small file. It keeps the six newest copies
plus the first copy from each of the seven latest days Parc was used, at most
thirteen. Each copy's name carries its UTC time and a number one higher than
the last copy's, and "newest", the hourly check and both retention rules follow
that number. A copy stamped while the Mac's clock ran ahead therefore never
outranks later copies once the clock is fixed, and it ages out within about a
week of use instead of waiting for real time to catch up. Each copy passes the
startup loader's decode and validation before an atomic write, and leaves out
history and downloads. Private windows, `--parc-profile` profiles and
model-test stores write none.

**Rescue.** If `session.json` exists but can't be read or validated, startup
shows a standard system alert, a Core Foundation user notification that needs
no app window or finished launch. Restore Backup takes the newest copy that
passes the loader's checks, skipping copies this version can't read, damaged or
newer, and the alert says how old it is; a copy stamped after the current time
says its age is unknown instead of showing a future date. The unreadable file
stays beside it as `session-unreadable-<UTC time>.json`: a hard link (or copy)
is made before the backup is swapped in atomically, so nothing is lost and a
newer Parc's file can be put back by hand. Quit changes nothing, so an older
Parc never replaces a newer Parc's file unless the person chooses to restore.
With no usable copy the "Parc couldn’t start" alert says whether backups are
missing or unreadable, and Parc quits as before. A restored sidebar's Downloads
list refills from the engine. If `session.json` is missing but a copy passes
the checks, the same alert, worded for a missing file, offers Restore Backup or
Start Empty. Starting empty is the safe choice there because no file needs
protecting, and an alert that can't be shown starts empty too. First launch and
a folder with no usable copies start empty without asking, as do
`--parc-profile` profiles, which keep no backups. `--parc-smoke` never asks: it
starts empty when the file is missing and reports an unreadable one. The
automatic backups and this rescue cover recovery; no window lists the backups
for browsing or choosing an older one.

**Privacy.** Copies follow the main file's rules. Clearing history over a time
range removes every copy stamped since the range began, so all of them for all
time, and also every copy whose stamp is out of step with its number: one taken
after a later-stamped copy, or before an earlier-stamped one. A copy taken after
one inside the range therefore can't outlive the clear, and neither can a copy
saved while the clock was set behind, as long as an earlier, correctly stamped
copy remains to show the jump; with no such copy, nothing in the stamps or
numbers can reveal it. With a correct clock no copy is out of step, so the clear
removes exactly the copies taken since the range began. Deleting particular
visits, as the history page does, removes copies that hold one of those exact
addresses unless the current sidebar still holds it. Clear Archive removes every
copy, and finishing a Profile's removal, including the data of a deleted Space
that was its last user, removes every copy that mentions that Profile. Each
clear leaves a fresh copy of the current sidebar and removes leftover temporary
save files. Deleting single tabs, archived items or a Space that shares data
leaves older copies, which age out within about a week. Kept unreadable files
are left alone: they are the person's own data, perhaps from a newer Parc, and
this version can't safely rewrite them. `tests/ParcCoreTests/Data/Store/SessionBackupTests.swift` covers
the schedule, cadence, validation, rescue choice, write order after a clock fix,
the kept file and pruning, including range clears with a clock that was set
behind. `SidebarRescueTests` (`tests/ParcTests/Data`) cover the rescue wording, the
missing-file offer and the starts that never ask.

## Dock, reopen and closing windows

Dock New Window and New Private Window use the actual engine/Profile readiness
gate. Reopening prefers an existing key window, then the last active live
candidate. A minimized candidate is made key through the native path; otherwise
it is brought forward. With no eligible window, Parc creates a standard window
without opening the command bar. Closing or retiring windows are not candidates
for another reopen.

## Moving selected content between windows

Selecting a shared tab, Favorite or split in another regular window moves its
actual native page ownership. It does not create a second page, replay the URL
or ask permission merely to transfer. Pending creation is not an existing
holder, and a failure leaves ownership unchanged and reports failure through
the normal action feedback.

The previous window becomes a placeholder for that item. It receives a frozen
viewport image of the moved content with a 0.6-opacity treatment over its theme.
Notes and Easels use their document drawing paths. Image decoding happens off
the main thread at pane size; explicit user captures have priority over the
shared capture slot. The placeholder is not a live page or an updating mirror.

The image belongs to the tab, not to a window. Every window showing that tab's
placeholder, however many, uses the one image and scales it to its own pane. It
is kept only while some window shows the placeholder, and a private window's
images never reach a regular window. The engine copies any pane the receiving
window shows, not only its focused one, so every pane of a moved split gets an
image; the focused pane's copy is taken first. The receiving window takes the
copy even when it isn't in front, as after a return to a background window: the
placeholder's own capture lease skips only the key-window rule and copies only
the whole visible page, while the active app, a visible unminimized window, no
sheet or security prompt and the screenshot policies still apply. A person's
own captures keep the key-window rule. The copy is tried six times over about
two and a half seconds before the pane is left plain.

Clicking or activating the placeholder through accessibility moves the actual
content back without reloading it. The last browser window stays open. A
placeholder does not expose live page commands or pretend its selected row and
address are a locally owned renderer. Placeholder state is not persisted.

Deselecting can return the most recent eligible placeholder once per deselection,
without activating its window. When an owning window closes, recent willing
windows are offered the content first. A failed split handoff restores the
page ownership rather than losing part of the collection.

## Transfer boundaries

The transfer registry reserves both sides while ownership changes, blocking
conflicting rendering, navigation and close requests. The existing WebContents,
history, form state and media remain attached to the moved page; picture in
picture and DevTools are keyed to that page rather than a newly loaded URL.

If the final owner cannot be established, both claims remain reserved and the
close flow offers Retry, Close or Keep Open. It does not silently discard the
content. Live Notes, Easels and Peek require a visible, unminimized destination
without an attached sheet; a plain page can move out of a minimized source.

Peek travels with its original parent collection. Reopen/Undo restores a whole
split even when another window holds it, and Reopen and Undo Close Peek both
move a parent page another window holds here before opening its Peek. Closing a shared row first moves it to
the requesting window, then uses that window's close/Undo ownership; a split
or multi-row selection held elsewhere moves all its pages first, and refuses
only when one can't move. Close isn't offered while a page is still opening, and
a Note there that can't save is explained before anything moves. If the close
still can't begin once the pages arrive, the window says why and each page goes
straight back to the window it came from, so the requesting window keeps its
selection and placeholders as they were. A page that can't go back, such as a
Note that still can't save, stays here showing its problem; a close the person
declines at a leave-page prompt takes the ordinary return. Commands that require
a live page are available only to its current holder.

A placeholder image can briefly show backing while a frame is captured, encoded
or fitted to a new pane size. The image is descriptive only; failure to obtain
one must not break the ownership transfer.

## Stay on Top

Stay on Top belongs to an exact regular window and persists with that window's
stable ID. Missing legacy values default to false. Enabling captures the normal
native level; disabling restores that level. Private windows can use the live
setting but do not persist it, and popup windows are excluded.

Menu and command actions revalidate the captured window before changing its
level, so delayed actions cannot affect a different key window.

## Shared folder and Pinned disclosure

Folders and the Pinned section open and close together in every window showing
that Space, on purpose. A folder's disclosure is stored on the folder and the
Pinned fold on the Space, so tidying one window's sidebar tidies the others
and the choice survives relaunch. See
[the Pinned section](sidebar-resize.md#pinned-section).

## Sources and validation

Window presentation/session storage, `LaunchContinuity`, the native page
transfer registry and `BrowserWindowController` own these paths. Focused model
coverage includes `WindowPresentation`, `ClosedItems`, `CloseUndo`,
`PagePlaceholder`, `PagePlaceholderImages` and session-store tests. Native/compiler checks validate their
interfaces when run. `tests/TerminationRestart/check.py` runs the real
termination coordinator against stand-ins for every way a quit can stop short.
