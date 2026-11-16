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
the same rule through [embedded page retirement](easel-embedded-pages.md#admission-and-lifetime).

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
image; the focused pane's copy is taken first.

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
interfaces when run.

## Remaining behavior and explicit deferrals

The explicitly deferred cross-window case remains: an automatic return to a
non-key window can leave a blank frozen placeholder. See
[the backlog](backlog.md#deferred).
