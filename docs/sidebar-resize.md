# Sidebar resizing and layout

The sidebar has a per-window width, an app-wide default for new windows, and
one native layout owner. Dragging its edge changes the existing page host;
it does not recreate the page or a second window.

Related contracts: [motion](sidebar-motion.md),
[accessibility](sidebar-accessibility.md), [Spaces](space-management.md),
[split views](split-groups.md), and [window restoration](windows-lifecycle.md).

## Source map

| Responsibility | Source |
|---|---|
| Width gesture and persistence policy | `Sources/ParcCore/SidebarResize.swift` |
| Edge hit testing, cursor, indicator and haptics | `Sources/ParcApp/SidebarResizeRegion.swift` |
| Header, list and dock geometry | `Sources/ParcApp/SidebarChromeLayout.swift` |
| Window integration and final layout | `Sources/ParcApp/BrowserWindowController+Sidebar.swift`, `Sources/ParcApp/BrowserWindowController+ChromeLayout.swift` |
| Renderer-paced page sizing | `Sources/ParcCore/PageContentResize.swift`, `Sources/ParcApp/PageContentResizer.swift` |
| Renderer reports and observation leases | `Sources/ParcApp/PageRenderFrames.swift`, `Engine/ParcNative/native_appkit_page.mm` |
| Space header and menus | `Sources/ParcApp/SidebarSpaceHeader.swift`, `Sources/ParcApp/SidebarSpaceMenu.swift` |
| Favorites empty state and dock | `Sources/ParcApp/SidebarFavoritesEmptyState.swift`, `Sources/ParcApp/SidebarDockStrip.swift` |

## Width gesture

`SidebarResizeGesture` is the pure state machine. Its owner starts one session
for an eligible locked or floating sidebar, applies each effective width to
layout, and persists only the completed result.

| Rule | Value or behavior |
|---|---|
| Default width | 228 points |
| Allowed committed width | 164–500 points |
| Hidden preview | Proposed width below 82 points |
| Collapse on release | Locked sidebar only, proposed width at or below 82 |
| Default-width snap | Within 14 points of 228, after leaving the band once |
| Snap entry speed | Below 50 points/second, moving toward the default |
| Snap-release haptic | Only after holding the snap longer than 0.5 seconds |
| Double click | Reset this window and the new-window default to 228 |
| Cancellation or failure | Restore the width at the start of the gesture |

The proposed width rounds to the nearest point, with halves away from zero.
Non-finite inputs do not change the live gesture. Collapsing restores the
starting width as the retained width, so revealing the sidebar restores its
previous size. A floating sidebar clamps at the minimum rather than committing
a collapsed state.

The resize strip is 8 points wide, centered on the trailing edge, inset 11
points from the window's top and bottom. It is not an accessibility element.
Its cursor applies only when the actual hit view is the strip or its child;
visible interactive child windows can obstruct it. Cursor rectangles stay
disabled for the drag and are re-enabled on every completion path.

The indicator appears after 0.25 seconds of hover and fades over 0.2 seconds.
A snap pulses its horizontal scale and gives generic haptic feedback. Reduce
Motion skips the pulse. Leaving the window, hiding the strip, closing or losing
key status cancels an active drag once and restores its starting width.
Stale fade completions cannot hide a newer indicator.

## Width across relaunch

`SidebarWindowWidth` keeps each window's width separate from
`BrowserSettings.sidebarWidth`. A completed drag or reset changes that window
and the default for future windows, without resizing other open windows.
Settings' width control deliberately broadcasts to every window of the same
store. If Settings changes during a drag, the active drag's final commit wins.

`BrowserWindowRecord` stores a window's width alongside its explicit identity,
selection and presentation. Older records without a width decode as 228;
restored and default widths are clamped to the supported range.

`BrowserStore.windowRecords` is separate from published UI state. Updating
records schedules persistence without rendering every browser window. Every
session write preserves the records. Private stores keep no persistent window
records.

`AppDelegate.recordWindowSessions()` records ordinary non-popup windows. The
frame-autosave holder is first, followed by front-to-back windows and then
other open windows; unopened saved records are retained by identity. Quit
captures the list before its own close callbacks remove windows.

AppKit restoration matches saved windows by identifier and passes the matching
record into `BrowserWindowController`. If no window is restored, the initial
fallback can use the first unrestored record. With session restoration off,
startup uses the app-wide default instead. A cancelled drag or collapse changes
neither the last-used width nor the record's width.

The fallback still uses AppKit's shared frame autosave. If its former holder
closed before quit, that saved frame and the first remaining width record can
come from different windows. Broader restoration belongs to
[Windows and lifecycle](windows-lifecycle.md).

## Page size during a width drag

`PageContentResizeReasons` combines independent resize owners:

| Active reason | Page sizing mode |
|---|---|
| None | Intrinsic: follow layout immediately |
| Sidebar drag, split-divider drag, live window resize or fullscreen transition | Throttle: allow one unacknowledged size |
| Interactive split editing | Locked: retain the size at entry |

Locked mode takes precedence over throttling. Window and split owners set and
clear their own reasons; clearing one must not end another owner's hold.
Only visible panes receive a held mode. Parked background pages stay intrinsic
and start no renderer observation.

`PageContentResizer` holds the page at the content's top-leading corner and
clips it while its renderer catches up. A new page cannot join a held mode
until both page and content have nonempty geometry. In throttle mode it queues
at most one size; a renderer report releases the hold. Size comparisons allow
1.00001 points of tolerance.

The engine reports the primary main frame's activated viewport in points.
`PageRenderFrames` converts that renderer size back to the page view's size,
including the infobar shelf and docked developer tools. The observation lease
ends on invalidation, release, page close or WebContents destruction and
follows renderer-widget replacement. A page without the reporting capability
resizes intrinsically; locked mode does not need reports.

A changed page frame is flushed into the native hosted hierarchy in the same
layout pass. This prevents the compositor retaining an old surface after a
sidebar or split size change. An unchanged, clean hosted frame skips the
recursive flush. Dirty geometry is checked shallowly, stopping at the docked
DevTools pane, which owns its internal frames.

A page replacement resets the hold, last report and observation. When a page
moves to another pane during a drag, the old subscription can remain until the
old pane next changes mode; its reports affect only that old pane. Rejoining
resets the previous hold. Any renderer frame report releases the hold; it does
not need to match the requested size. If no new frame arrives, the current
size stays held until a report or the drag's end.

## Sidebar chrome spacing

`SidebarChromeLayout` is the source of geometry for both the full layout and
bounded animated layout. Avoid duplicating its arithmetic in view owners.

| Region | Contract |
|---|---|
| Navigation row | Starts 4 points down, 40 points tall; narrow layout below 212 points |
| Address row | 8-point horizontal inset, 36-point field, normally beginning at y = 46 |
| Page toolbar enabled | Collapse the sidebar address row unless a prompt or keyboard search needs it |
| Favorites tray | Immediately below the header; the Space page follows without a gap |
| Empty dismissed tray | No tray height; 5-point header-bottom spacing unless a Space header is shown |
| Space header | 36 points tall; 8-point top spacing without Favorites, zero with Favorites |
| Tab list | 8-point side insets; 16-point indentation per folder level |
| Ordinary item slot | 40-point cell plus 1-point gap; visible 36-point row centered vertically |
| Pinned header / Today divider | 3-point / 25-point row slots |
| List bottom | 120-point inset |
| Dock | 50 points tall; 32-point leading and trailing controls at 8-point side insets |

The header's address space also accommodates shared quotes and live keyboard
sessions. Those owners must use the same geometry rather than preserving an
empty row when the address moves into the page toolbar.

The dock's Space strip uses available width minus its own 2-point side insets.
Item pitch clamps to 8–34 points. Below 22 points it switches to the compact
style, retaining more width for the selected item and scrolling when needed.
Dragging hides the source item and reserves insertion space. A singleton Space
without a custom icon can omit the strip; creation feedback remains visible.

## Space header

A regular window shows the header for two or more Spaces, an authored title,
a custom icon, or the Show Space Header setting. Private windows use their
own heading. Untitled Spaces now have an optional model title and display the
positional `Space N` placeholder; a literal authored title is not inferred
from its resemblance to that placeholder.

`SidebarSpaceHeaderView` supports inline rename, the icon picker, profile
selection, and the shared Space menu. The active Space and Spaces manager use
inline editing; renaming an inactive Space outside the manager uses a sheet.
Commit callbacks validate the window, Space and profile before writing.
Cancelling edits preserves the prior title.

The name has the `sidebarSpaceName` accessibility identifier. Its placeholder
is a placeholder value rather than authored text. The masked field fades long
editable text without changing stored content. The hover edit button appears
after 0.1 seconds, becomes Done while renaming, and clears hover when hidden or
when its window loses key status.

### Dock Space menu

The header and dock share `SidebarSpaceMenu`. Available actions include
renaming, theme editing, icon selection, profile assignment, creating a folder,
turning a Space into a folder, deletion when allowed, and opening the Spaces
manager. Actions operate on the chosen Space and revalidate it at execution.
Show/Hide Space Header is available for a single untitled Space without a
custom icon. Sharing and service-backed live folders remain excluded.

### Sidebar Space menu

The list's empty-area context menu uses the same Space actions, so a hidden
header can be shown again there. Item rows keep their own contextual actions.
Drops on a header target the top of that Space's pinned items; dock drops use
the same move ownership and profile checks. Whole-split and multi-item behavior
is described in [split views](split-groups.md) and [folder moves](folder-moves.md).

Collapsing the entire pinned section is not implemented; the header does not
expose a collapse chevron or action.

## App Tray empty state

A profile with no Favorites and no stored dismissal shows the Favorites card.
Private windows show no tray. Its height fits the wrapped title, subtitle and
symbol, with a 63-point minimum; it remains readable at the minimum sidebar
width.

Dismiss and Hide record the profile once in
`topAppsEmptyStateDismissedForProfiles`. All windows of that profile update;
other profiles retain their cards. Older sessions default to undismissed.

The whole card accepts a Favorites drop. Dragging changes its dashed border
to solid, and dropping the first Favorite replaces the card with the grid.
After dismissal, the header's 5-point band remains a drop target. The card
exposes its image, text and Dismiss button in that order. Dismiss participates
in the keyboard chain; removing it leaves focus at the next valid stop.

## Checks

These existing focused checks cover the production models and inert AppKit
components; inspect a check before running it under the current work contract:

| Check | Coverage |
|---|---|
| `tests/SidebarResize/check.py` | Gesture thresholds, snapping, cancellation, per-window persistence, renderer holds and native-host sizing |
| `tests/SidebarResize/engine_report.py` | Required reporting symbols in a sealed framework, without launching it |
| `tests/SidebarChrome/check.py` | Header/list/dock geometry, Space header and settings wiring |
| `tests/SidebarFavoritesEmptyState/check.py` | Card layout, persistence, drag state and keyboard dismissal |
| `tests/SidebarOutline/check.py` | Row geometry, disclosure and accessibility wrappers |
