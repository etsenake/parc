# Browser window lifecycle

Regular windows retain stable identities, their Space and selected content,
focused panes, sidebar mode/width and activity dates. Each live page has one
window owner even when the same shared sidebar item is selected elsewhere.

## Restoration and launch continuity

AppKit restores regular windows by stable ID and owns frame, minimized and
fullscreen restoration ordering. Restoration does not bring every window to
the front. If a saved Space no longer exists, that window falls back to the
first available Space without changing another window's selection.

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

OS logout/system shutdown handling through asynchronous termination has not
been separately validated. Normal quit and persisted-state logic are not proof
of that system-driven lifecycle.

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
split even when another window holds it. Closing a shared row first moves it to
the requesting window, then uses that window's close/Undo ownership. Commands
that require a live page are available only to its current holder.

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

## Sources and validation

Window presentation/session storage, `LaunchContinuity`, the native page
transfer registry and `BrowserWindowController` own these paths. Focused model
coverage includes `WindowPresentation`, `ClosedItems`, `CloseUndo`,
`PagePlaceholder` and session-store tests. Native/compiler checks validate their
interfaces when run.

No application was launched for this documentation cleanup. Source and model
coverage do not establish real AppKit restoration order, OS logout behavior,
placeholder appearance or uninterrupted live media during every transfer.
