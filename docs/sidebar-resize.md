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
| Edge hit testing, cursor, indicator and haptics | `Sources/Parc/SidebarResizeRegion.swift` |
| Header, list and dock geometry | `Sources/Parc/SidebarChromeLayout.swift` |
| Window integration and final layout | `Sources/Parc/BrowserWindowController+Sidebar.swift`, `Sources/Parc/BrowserWindowController+ChromeLayout.swift` |
| Renderer-paced page sizing | `Sources/ParcCore/PageContentResize.swift`, `Sources/Parc/PageContentResizer.swift` |
| Renderer reports and observation leases | `Sources/Parc/PageRenderFrames.swift`, `Engine/ParcNative/native_appkit_page.mm` |
| Space header and menus | `Sources/Parc/SidebarSpaceHeader.swift`, `Sources/Parc/SidebarSpaceMenu.swift` |
| Pinned header and fold state | `Sources/Parc/SidebarPinnedHeader.swift`, `Sources/ParcCore/PinnedSectionCollapse.swift`, `Sources/Parc/BrowserWindowController+PinnedSection.swift` |
| Favorites empty state and dock | `Sources/Parc/SidebarFavoritesEmptyState.swift`, `Sources/Parc/SidebarDockStrip.swift` |

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
selection, presentation and frame. Older records without a width decode as 228;
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

### Window frames

Each record keeps its own window's frame (`SavedWindowFrame`), refreshed when
the window moves or resizes. A full-screen window keeps the frame it had before
entering full screen. The frame is an optional extra key: older records load
without one, an older Parc ignores it, and a damaged frame is dropped without
failing the session.

AppKit's own restoration places the windows it reopens and ignores this frame.
When AppKit reopens nothing, for example when Parc is opened with Shift held or
the system's saved window state is gone, the fallback window takes the frame of
the record it restores, so its position, size and sidebar width all come from
the same window. The frame is fitted to today's screens: one that still fits a
screen's visible area is kept; otherwise the window moves to the screen holding
most of it, or the nearest one, shrinks to fit and slides the shortest way back
on screen. A window saved in full screen returns at its windowed frame, and a
record without a frame is centered as before.

New windows start from AppKit's shared frame autosave, then step down and right
from the front browser window. AppKit gives that slot to the first window to
open and never passes it on when that window closes, so whenever no open window
holds it, recording the windows writes the leading record's frame into it,
unless that window is full screen. A window opened with none open, or the first
window of a launch with restoration off, appears where the latest front window
was rather than where a long-closed one sat. Broader restoration belongs to
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
| Pinned header | An ordinary item slot with pinned items, otherwise a 3-point drop band |
| Today divider / Incognito heading | 25-point slot / 36-point heading in a 37-point slot, like the Space header; neither is a row |
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


## Pinned section

A Space with at least one pinned item shows a Pinned header above its pinned
rows: an 11-point "Pinned" label and a chevron in the rows' close-button column,
both centred. The header takes the same row slot as New Tab and tab rows, as
does an empty Library card's plain Pinned label, so its hover and press plate
has their height, 12-point continuous corners and full width, and a drag over
it lights the row with the same 12-point corners a folder gets. Clicking the
header, its context menu, View → Collapse Pinned (Expand Pinned while folded)
or the same command in the command bar folds or unfolds the section. An empty
Pinned keeps the 3-point drop band and no header. Rows slide and fade over 0.25
seconds and the chevron turns over 0.2 seconds; Reduce Motion makes both
instant.

Folded, the header says what it hides. By default it shows the favicons of the
first four pinned tabs, in sidebar order through folders and splits, each on a
small tile that cuts a clean ring out of the one beneath, then +N for the rest.
Settings → Advanced → Show icons when Pinned is collapsed, the header's context
menu and Show/Hide Collapsed Pinned Icons switch every window at once to a count
pill in the Space's colour, which suits screen sharing. That preference is
app-wide. A narrow sidebar folds icons into the count before the summary would
reach the chevron.

The active tab stays visible. When it lives in a folded Pinned it peeks out
under the header, with its folder path, the way a closed folder shows its active
tab, and it shows even with icons turned off. Selecting another tab tucks it
away again.

The fold belongs to the Space, the way a folder's open or closed state belongs
to the folder: every window showing that Space folds and unfolds together, on
purpose, and the Space saves it, so it survives relaunch (`PinnedSectionCollapse`
and `BrowserStore.setPinnedSectionCollapsed`). A Space with nothing pinned shows
no header and can't be folded. If a folded Space loses its last pinned item, the
next tab pinned there arrives folded and shows up in the header's summary.

While Pinned is folded:

- A drop anywhere in the header's row lands at the top of Pinned. Holding a
  drag there for the system spring-loading delay unfolds it, and it folds again
  if the drag leaves or is cancelled. A drop in the band under the header's row
  lands at the end.
- Arrow-key browsing and Control–Space skip the hidden rows but reach the
  peeking tab. Number shortcuts and Next/Previous Tab still count pinned tabs,
  so Command–1 keeps its tab, which then peeks out.
- Select All and multi-selection act on the visible rows only.
- Library Space cards list the whole Pinned section without a header. An
  entirely empty card shows a plain Pinned label instead, and its whole height
  takes a Pinned drop with the same highlight.
- VoiceOver reads the header as a disclosure triangle, "Pinned, 6 tabs" when
  folded, and its outline row reports the same state.

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
| `SidebarResizeGestureTests`, `SidebarWindowWidthTests`, `SidebarWindowSessionTests`, `SavedWindowFrameTests`, `PageContentResizeTests` | Gesture thresholds, snapping, cancellation, per-window persistence and frames, screen fitting and the renderer hold model |
| `SidebarResizeRegionTests`, `PageContentResizerTests` | Resize region and page resizer |
| `PageRenderFrameHoldTests` | Renderer frame reports |
| `tests/SidebarResize/engine_report.py` | Required reporting symbols in a sealed framework, without launching it |
| `SidebarChromeLayoutTests`, `SidebarTablistTests`, `SidebarListMenuTests`, `SidebarSpaceHeaderTests` | Header/list/dock geometry, Space header and settings wiring |
| `FavoritesEmptyStateViewTests` | Card layout, persistence, drag state and keyboard dismissal |
| `SidebarOutlineTests` | Row geometry, disclosure and accessibility wrappers |
| `PinnedHeaderTests`, `PinnedOutlineHeaderTests`, `PinnedPlateGeometryTests` | Fold state, peeks, the folded summary and its drawing, the header plate measured against New Tab's, header drops, keyboard order, commands and the icon setting |
