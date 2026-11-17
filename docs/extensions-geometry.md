# Extension geometry and artwork

Extension identity, permission, pin order and page lifetime stay with the native
extension model. App controls supply presentation around genuine Chromium
artwork and commands. See [interaction](extensions-interaction.md) and
[lifecycle](extensions-lifecycle.md) for input and retirement.

## Reference and finite comparison

| Surface | Parc layout |
|---|---|
| Sidebar pins | Adjoining 28 × 28 buttons, radius 9, zero stack spacing; compression hides whole buttons only. |
| Page-toolbar pins | 32 × 24 buttons, radius 6, centered in the pane bar. |
| Icons | Chromium's 32-point canvas contains 16-point icon ink; draw the canvas at its own size rather than shrinking the ink to 8 points. |
| Site Control Center | Four columns of 48 × 32 tiles, 8-point spacing; 14-point pin badge, 8-point bold glyph tilted 33°. |
| Popup | A genuine titled/closable child NSWindow, initially 300 × 300 content when no size is available. |
| Side panel | Trailing native page container, 30% preferred width bounded to 240–360 points and clipped to available space; 32-point header. |

`ExtensionActionButtonCell` centers the canvas without mutating the copied image.
Blocked decoration and grayscale remain upstream-owned. The view permits badge
overhang while retaining the original action lease.

Pinned badges use the unbadged canvas plus the extension's own foreground and
background colors. The pill sits at the icon's top right, overhanging 4 points
up/right, 11 points high, and grows leftward from an 11-point circle to 26 points
with bold 8-point text. It passes clicks through and exposes badge text as the
button's accessibility value. Missing unbadged imagery/colors falls back to the
original baked image, never two badges. The Site Control Center applies the same
badge within its tile, clear of its separate pin indicator.

Context menus use the current Chromium menu model and model lease, presented as
Parc's themed menu beside the tile or pinned button. An open Site Control Center
stays open; its source tile remains highlighted. Disabled-row reasons appear in
tooltips. Card/menu chains clamp to the visible window and can open leftward.
See [Site Control Center](web-interactions.md).

## Popup anchor

A popup opens just below the control that opened it and never covers that
control or the bar it sits in. Each time the presenter places or resizes a
popup it asks the browser window's controller for an origin, passing the
extension, the popup window and its full frame size; the controller answers in
screen coordinates ([`ExtensionPopupPlacement`](../Sources/ParcApp/ExtensionPopupPlacement.swift)).
The presenter's own sidebar, focused-view and window anchors remain for windows
whose controller gives no answer.

The controller picks the anchor in this order:

1. The button that was clicked for that extension, while it's still visible:
   a pinned button in the sidebar's URL bar or any pane's or Peek's toolbar, or,
   for an extension launched from the Site Control Center or its held-Command
   picker, the button that opened the Site Control Center. The popup that
   click's action opens claims it and only that popup reuses it; a click whose
   action opens no popup is forgotten at once. So a later popup from the
   command bar, a shortcut or the extension itself never lands on an old
   button.
2. The address area that owns extension buttons: the sidebar's URL bar while
   it's presented and shows the address, else the focused pane's or Peek's
   toolbar, else a pop-up window's chrome. Within it the extension's own pinned
   button, else the Site Control Center button.
3. A point 40 points in from the top trailing corner of the focused page, or of
   the window when there's no page.

The popup's trailing edge lines up with the button's and its top sits 6 points
below the lower of the button and its bar, so a toolbar click opens beside its
button whether or not the sidebar is open, and a sidebar click opens below the
URL bar. It keeps 8 points inside the window's visible part, sliding inward
horizontally. Without room below it flips up 6 points above the bar, then opens
beside the bar, level with its top and leading side first. When none of those
fits in the window it tries them on the screen's visible frame, hanging past
the window's edge rather than covering the bar; then beside the button, which
keeps the button clear; and only then slides up over the bar. In a stacked split
the lower pane's popup drops into the lower pane when it fits and flips up over
the upper pane when it doesn't.

Anchor frames reach the screen through AppKit's window conversion, and the
presenter's focused-view anchor converts through window coordinates too, so the
flipped window content can't swap a stacked split's panes. A popup the user
drags keeps its place across resizes. Native host initialization and resize
validation remain responsible for actual page size.

## Side-panel compatibility adaptation

The panel is a sibling of the page, below capture/popup chrome. Its native header
uses the shared 32 × 24 close control and an Extension accessibility label.
Header and body form an explicit focus scope; only the body is a page owner.
Close and Escape invoke the real native service. Resize adjusts the existing
container and real extension page without re-navigation. Details:
[side-panel boundary](extensions-side-panel-adaptation.md).

## Checks

Geometry checks cover image-only cells, narrow/zero-sized panel fit, header,
close/Escape and the real layout policy. Native compiler and whole-module Swift
checks cover bridge integration.
