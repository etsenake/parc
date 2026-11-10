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

The anchor uses the visible sidebar placeholder, otherwise the actual focused
pane or Peek card, otherwise the original window. A toolbar button does not
replace the content anchor. With full popup size `(W,H)`, parent frame `(Pw,Ph)`,
sidebar width `S`, and focused view rect `R` converted into parent content:

- Sidebar origin: `(max(S-W-40,40), Ph-H-10)`.
- Focused content: `(R.maxX-W-40, R.maxY-H-10)`.
- Window fallback: `(Pw-W-40, Ph-H-10)`.

Convert through the same parent window into screen coordinates. Native host
initialization and resize validation remain responsible for actual page size.

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
