# Window appearance and transitions

This guide describes standard, private and popup window surfaces.

## Private unpinned heading

Private Today content uses “Incognito Tabs” in a 36-point heading, with insets
8 top, 14 leading, 2 bottom and 8 trailing. The leading inset shifts by 3.5 when
the sidebar indicator is present.

When the normal store contains multiple Profiles, a passive Incognito capsule
identifies the private context. It uses the eye-slash symbol, an 11-point medium
label, a 20-point icon slot and a two-point gap. The capsule has no action and
must not become a Profile-switch control.

## Private window theme

An ordinary private window always uses Dark Aqua with opaque Display P3
(0.054, 0.060, 0.075), independent of the selected Space. Its static blue semantic
palette drives controls; the resting URL field uses white at 0.15. The window
and floating/docked sidebar suppress material/theme canvases. A locked sidebar
shows the window's own background.

The plus HUD, history chooser, tooltips and recent-tab switcher receive the
private palette. Download review uses the private surface and Dark
Aqua. Toasts and the Press Again cue use the private background through the
shared [toast palette](toasts.md). Private popups currently retain their Space's
theme with Dark Aqua.

Show Toolbar is one preference shared by ordinary and private windows. Hiding
it restores the sidebar URL/navigation controls. An empty window does not gain
a private-only toolbar rule.

## Popup native window class

Page-created popups use a dedicated NSPanel: not restorable, not hidden on app
deactivation, eligible to become key/main and managed by normal Spaces. Existing
native binding, close delegation, requested geometry and session exclusion stay
with that panel. Minimum content size is 300 × 360; its background is movable.

Making it key temporarily uses level 24, then a weak queued callback restores
normal level and removes `moveToActiveSpace`. The reset is idempotent and never
activates another window.

The 47-point popup strip contains conditional Back, address, Copy and Extensions
controls. Back is 31 points with a 16-point glyph. The rounded address field has
a 31-point minimum height; its title changes from 13 to 11 points while loading.
Copy uses the actual page URL. Existing commands remain available independently
of which buttons fit in the strip.

The address context menu and accessibility action retain Site Control Center
access when Extensions is absent. Both revalidate the original key window,
security admission, native page binding, document revision and lifetime.
Site Control Center still lists extension actions only. Enabled extensions
without an action are absent from its content even though the native catalog
includes them; the shell needs to consume that catalog.

## A window with no tab

A window with no tab uses `SplitPanePlaceholder`, the same pending content as
Add Split. It accepts no input and exposes “No tab open” to accessibility. Its
six-point rounded translucent card follows the window appearance: white at
0.666 in light appearance and 0.1 in dark appearance, over the window backdrop.
A blank tab is a real white page and follows its own content-focus request.
The planned [start page](start-page.md) replaces this placeholder in an empty Space.

## Page card shadow

`ContentShadowImage` caches a 51-point stretchable image per backing scale: a
10-point outset, six-point corner radius and nine points of straight edge on
either side of the stretchable point. The ordinary shadow is black at 0.25,
radius 3 and offset (0, 1), rendered with a Core Graphics blur of 6.

The image clears the card's interior through the continuous-corner mask, so
translucent pages are not darkened and resizing never re-blurs. A lone card's
shadow is a sibling below its page host in the same sidebar-motion group. It
refuses hit testing/accessibility and hides for divided splits and full screen.

Divided splits own one shadow layer per pane. Placement follows actual AppKit
layer coordinates, including flipped hosts. The image changes only when the
layer is created or its backing scale changes; layout transitions move the
existing shadow with the pane.

## Checks

`tests/EmptyWindow`, `tests/ContentFocusRequest`, `tests/SidebarMotion` and
`tests/SidebarPacing` exercise colors, input/accessibility exclusion, focus,
shadow geometry and bounded animation work.
