# Sidebar accessibility and focus

The sidebar exposes controls, a structured item outline and a linked keyboard
path. Hiding it moves its existing views offscreen, so presentation, keyboard
focus and accessibility visibility are separate concerns.

The primary implementation is in `Sources/ParcApp/SidebarAccessibility.swift`,
`SidebarOutline.swift`, `WindowKeyViewLoop.swift`, `SavedFocus.swift` and
`SidebarView.swift`. See [layout](sidebar-resize.md),
[motion](sidebar-motion.md), [keyboard navigation](keyboard-navigation.md),
[selection](sidebar-selection.md) and [previews](sidebar-previews.md) for their
own behavior contracts.

## Inventory

| Surface | Accessibility and keyboard contract |
|---|---|
| Native window controls | AppKit close, minimize and fullscreen controls, ordered before sidebar controls |
| Sidebar toggle | Hide sidebar when locked; Lock sidebar when floating or hidden |
| Navigation | Go back, Go forward, Reload this page; Stop Loading while appropriate |
| Address pill | Button with current address; keyboard focus ring follows its current shape |
| Space header | `sidebarSpaceName` field, placeholder for an untitled Space, contextual management actions |
| Favorites | Each item's own actions; empty-state Dismiss joins the keyboard path |
| Item list | `AXOutline`, identifier `sidebarAllTabList`, containing rows and one column |
| Tab | Its button and custom actions inside the row's cell |
| Folder | Row disclosure attributes plus the cell's disclosure control |
| Split group | One row whose contents follow the group's current presentation |
| Library entry | Home label; flyout items expose individual buttons; entry itself is not a Tab stop |
| Dock Space | Space role description, title and `SidebarDockItem-<title>` identifier |
| Dock plus | New Tab, Folder, or Space; keyboard stop with a visible focus ring |
| Resize strip | No accessibility element |

AppKit can expose an `NSButtonCell` rather than its button. Labels therefore
belong on the button, its exposed cell and the image description where needed.
`SidebarAccessibility.label` is the shared helper. Tests should inspect the
unignored element rather than only the button object.

Disabled controls retain their place in the linked chain so enabling one does
not require a different order; AppKit skips controls that cannot currently
become key. Space dock buttons deliberately refuse first responder, but Space
shortcuts and accessibility press actions remain available.

The docked sidebar's Site Control Center and extension buttons appear on hover,
keyboard focus or an open menu, popup or panel, and stay exposed and keyboard
reachable at zero opacity. While VoiceOver is running they stay revealed, so
its cursor never outlines empty space; Parc observes VoiceOver turning on and
off and does not track the cursor. [Navigation](navigation.md#sidebar-controls-and-url-pill)
owns the full rule.

## Item list outline

`SidebarView.render` supplies ordered `SidebarOutlineEntry` values to
`SidebarOutlineView`. Each row has a stable key, geometry and disclosure state.
The row wraps an `AXCell`, which contains the existing item's own element;
wrapping a tab must not erase its title or actions.

The list includes the pinned header, pinned items, Today divider where needed,
New Tab and Today items. Private windows use their own heading. Folder depth
becomes `AXDisclosureLevel`, and visible direct children name the row that
discloses them.

### Row lifetime and virtualization

Rows retain stable accessibility identities while their keys remain. Item
views are built near the visible area, retained for a wider scrolling margin,
and released when sufficiently far away. An active rename or drag can retain
its view. Neighboring Space pages prepare rows with a bounded budget rather
than eagerly constructing every item.

A row without an attached view still reports its frame and parent through the
outline. Asking for its accessibility children builds its content. Moving
accessibility focus to an offscreen row scrolls it into view and ensures its
view exists. Do not replace this with one permanently attached view per item:
long lists would put all those views into AppKit's layout engine.

### Attributes and notifications

- `AXIndex` follows visual row order. Folder depth and parent relationships
  remain correct after insertion, reordering, expansion and collapse.
- A folder's `AXDisclosing` setter invokes its toggle without the pointer
  triangle's selection reset. Reconciliation removes only selections hidden
  by collapse.
- An empty Pinned's header band is expandable but childless. It stays
  collapsed; setting disclosure runs no action and creates no rows. With pinned
  items the visible Pinned header row reports whether the section is folded,
  and setting disclosure folds or unfolds it. Pinned rows stay its siblings at
  level 0, and the header itself is a pressable disclosure triangle.
- The outline exposes rows, visible rows, selected rows and one column.
  Selection includes the appropriate multi-selection or single selection and
  active item, filtered to visible model entries.
- Changes post `rowCountChanged`, `selectedRowsChanged`, and folder
  `rowExpanded`/`rowCollapsed` notifications.
- The outline is the focused accessibility element only when the sidebar's
  list stop holds keyboard focus, is presented and can become key, and at
  least one item row is visible.

Rows and the outline expose selection as read-only. Selection changes use
items' press and custom actions; direct accessibility assignment of selected
rows is not implemented. VoiceOver selection uses the existing item actions.

## Window key-view loop

`SidebarView.keyViewEntry` is a gate that never takes focus. It leads to the
sidebar's first eligible header control, through the sidebar chain and out
through the weak `keyViewExit`. When the sidebar is not presented, the gate
bypasses it immediately. Outside links enter through that gate, never directly
through a later member of the sidebar.

The sidebar's order is header controls, address and related controls,
Favorites and Space-header controls, the list stop, list controls in visual
order, mini-player controls, then the dock plus. The list stop provides
keyboard item selection and draws the appropriate item highlight. Clear Today
is available as a command and accessibility action but is not a Tab stop.

`WindowKeyViewLoop` connects page-side key views in geometric order to the
gate and back. Within an engine page, the renderer is the stop rather than
its focus-forwarding host. A Peek host that accepts Escape passes through to
its own controls and page. Parked panes, sidebar preview cards, closed loops
owned by capture UI, and panes dimmed behind an active Peek are excluded.

The window loop is not globally recalculated: capture overlays and preview
cards retain their own keyboard ownership. The linker runs after full chrome
layout, when a window becomes key, and when a newly swapped renderer takes
focus. Field editors remain with their fields. Unchanged correct links are
not rewritten.

With a hidden or absent sidebar, the page side loops on itself. With a shown
sidebar, Tab and Shift-Tab can traverse the two sides. Native engine focus
rotation uses this same path. A Peek host focused directly for Escape is not
itself a Tab stop; direct traversal from that host remains outside the linked
control path.

## Focus restored after a panel

Use `SavedFocus.mayReturn(to:in:)` before restoring a saved responder. It
requires the view to remain in the same window, to have no hidden ancestor,
and to belong to no `OffscreenPresenting` ancestor whose `isPresented` is
false. Field editors inside sidebar controls are covered by the ancestor walk.

Command sessions, Space creation cancellation, navigation history, Easel web
input, preview dismissal and window-move cancellation use this shared rule.
Each owner keeps its own fallback when restoration is refused. Page-only
restoration and onboarding-window focus have their own scopes and do not
need to manufacture a sidebar dependency.

The sidebar stays presented while it slides away. A restore can therefore
land there during the slide; the settling layout relinquishes that responder
to the window when presentation ends. It does not request page focus from
inside layout. Ending an inline rename completes through the normal editing
lifecycle rather than keeping a field editor offscreen.

Automatic selection uses `focusIfPresented`. Starting an inline edit uses
`presentsForEditing(reveal:)`: in a key window the reveal runs even if a hide
is still in motion, then editing proceeds only if the owner is presented.
This prevents selection and restored focus from silently reaching hidden UI.

VoiceOver's explicit focus requests are not blocked. The offscreen sidebar
remains exposed, and its actions must remain usable. This does not authorize
an automatic focus restore to that same offscreen view.

## Page controls opened from the sidebar

A hidden sidebar's `visibleRect` and `isHiddenOrHasHiddenAncestor` cannot tell
whether its anchor is on screen. Use `isPresented`.

Page controls opened from an unavailable sidebar anchor use the current page
or page host's top-leading corner. This applies to the Site Control Center,
page menus, site settings, blocked pop-ups and payment controls unless their
caller supplies a live toolbar anchor. Existing in-window bounds rules still
apply to menus and their submenus.

The sidebar's own item and dock menus keep their control ownership. A new page
popover should follow the shared hidden-anchor rule rather than presenting
from an offscreen control merely because that control is still accessible.

## Downloads entry

`SidebarLibraryEntry` occupies the dock's leading 32-point slot and exposes
Home. It does not take keyboard focus or draw an unmarked ring; its expanded
flyout contains individual accessible buttons. The trailing keyboard stop is
the dock plus. The Library's full interaction contract is in
[Downloads and Library](download-library.md).

## Row and mini player key views

Every keyboard stop needs a visible focus indication. Sidebar navigation and
action buttons use rounded rings; the address pill follows its current shape;
New Tab uses its row plate; row close buttons keep their exterior rings.
Toolbar and popup owners retain their own button styling and labels.

The mini-player deck includes Show All, each visible player row, its title,
transport buttons and volume control. Rows draw an exterior ring around the
card; Show All and titles use rounded rings, transport buttons their exterior
rings and the slider AppKit's ring. Focusing a player expands the deck, Return
reveals its page, and Space plays or pauses it. A change in players relinks the
sidebar chain. Keep these working keyboard paths even when modifying appearance.

## Control-Space announcements

The command field retains focus while the sidebar keyboard cursor moves.
There is currently no dedicated spoken announcement for each highlighted
sidebar item. Scope entry/exit and search-privacy announcements in
`CommandBar.swift` are separate and must not be mistaken for item narration.
Any future narration should announce user-driven movement, not ordinary list
reconciliation, and should preserve the command field's ownership.

## Checks

| Check | Coverage |
|---|---|
| `tests/SidebarAccessibility/check.py` | Exposed labels, chain ordering, focus guards, saved responder rules and source wiring |
| `tests/SidebarOutline/check.py` | Row/cell hierarchy, geometry, stable identities, disclosure and selection |
| `tests/SidebarWindowKeyLoop/check.py` | Bidirectional traversal, renderer replacement, hidden sidebar, Peek and closed-loop exclusions |
| `tests/SidebarMiniPlayerFocus/check.py` | Mini-player keyboard actions and visible rings |
| `tests/SidebarChrome/check.py` | Dock order, Space identifiers and header controls |
| `tests/SidebarWindowButtons/check.py` | Window controls and presentation-state pointer handling |
| `tests/SidebarHeaderGlyphs/check.py` | URL row button reveal rule, popup and panel holds, and VoiceOver |

These are model and inert AppKit component checks. Inspect their entry points
before running them under [AGENTS.md](../AGENTS.md). Review each new focus-restore
path against the shared saved-responder rule.
