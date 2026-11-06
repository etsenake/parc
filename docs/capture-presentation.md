# Capture selection and output presentation

CAP18 keeps the existing original-page capture owner and immutable PNG pipeline.
The selection surface, captured image, local crop editor and output palette now
share explicit geometry and appearance values. Crop, Portrait, Library, Messages
and Easel callbacks still belong to their existing owners; none of the display
code obtains pixels or changes a destination identity.

## Recovered contract

SHA-256 `4e452201e483b5480c0403a9ef8566e10515cdcb78828622ff9032b202e29547`.
The components, Swift-type, annotated-function and cross-reference helpers
resolved this slice; no new heavy decompilation was necessary.

  captured rectangle from its original window, expands it by four points and
  gives its top/leading/width/height constraints priority 750. Required image
  edges stay four points inside the page. `CapturedImageView` construction at
  seven-point outer corners and half that radius to the image.
  right side if its maxX plus 273 fits, otherwise the left; the gap is ten.
  vertical threshold. These anchors have priority 250; required page edges
  keep the palette inside ten-point margins. Parc applies that precedence with
  bounded frame calculations instead of conflicting AppKit constraints.
- Rows use a 14-point medium font, seven-point horizontal padding, 32-point
  high with a 13-point medium AppKit font and ten-point spacing
  keyboard selection, HoveredCellBackground for hover, and
  separate ordinary/selected/toggled text colors. The actual named values and
  camera cursor artwork are retained with [resource provenance](../Resources/Capture/README.md).
- The existing lens retains six-point focus expansion, four-point border,
  seven-point outer corners and the black 0.25/radius12/(0,8) shadow. Original
  black at 0.25. Parc now composes those same two live-page layers and resolves
  the original ImageViewBackground border for light/dark appearance.
- The lower instruction bubble uses 14-point semibold text at 0.8 opacity,
  values and the named colors with a restrained static gradient. The original layered blur is adapted to native static drawing; CAP24 recovers the actual instruction-state easing, hover opacity and
  lens spring in [capture motion](capture-motion.md).

## Production geometry and states

The controller retains a logical preview rectangle when it requests pixels.
Regions map the actual native rectangle; element captures include the native
two-point expansion and clipping; viewport/full-page requests retain the original
viewport. The displayed pixels fit that rectangle without distortion. Crop and
Portrait edits fit their new aspect ratio in the same original context. The
preview has the four-point frame and seven/3.5-point corners; normal-sized panes
use the recovered side and vertical palette anchors.

Narrow split panes (less than twice the palette width plus 30) deliberately use
separate image/palette bands. The palette takes at most 62% of available height,
scrolling genuine actions. This current-AppKit adaptation avoids hiding the whole
image behind an otherwise page-sized palette. Full-page images fit without
resampling their owned PNG. The local reversible crop editor remains the
user-approved shared-flow adaptation: it displays the original pixels above its
instruction card and maps the clipped selection back to an outward-rounded pixel
rectangle. Only `CapturedImage` commits the result.

Light/dark appearance changes resolve both AppKit text and layer colors. Ordinary,
hovered, keyboard-selected, combined, saved-toggle and disabled states use their
own inks. Disabled output rows keep truthful availability; busy Library and
Messages states retain the existing callback gates and status message. Search
keeps the empty-result surface. Entering capture/configuration clears old crop
outlines and image frames. The Cancel and visible-area controls remain explicit
keyboard-accessible Parc additions. The system cursor uses genuine artwork with
an explicitly adapted native hotspot, without copying the renderer or adding a
second image owner.

Both recovered palette shadows are separate AppKit layers. AppKit rasterization
and rounded corners replace SwiftUI continuous curves, and the instruction
card uses a static native gradient instead of the source layered blur effect.
These platform render adaptations preserve the recovered geometry, colors and
state distinctions without a duplicate SwiftUI presentation owner. No haptic or
new timing is invented by this row; CAP24 adds the separately attributed motion.

## Ownership and validation

CAP17 owns entry/admission and the live recognizer forwarding API:
`PageCaptureController.handleCaptureGesture(_:)` →
`PageCaptureOverlay.handleCaptureGesture(state:point:)`. CAP18 owns this overlay's
static layout/drawing and `CapturePresentation`; both preserve the same freeform
selection fields and opaque native target tokens. CAP19 owns Portrait controls
and compositor fidelity, CAP20 destination ordering/attribution, CAP21 richer
editing/context variants, and CAP24 motion/focus/haptics. The existing callbacks,
original page/Profile/Space/window leases, output bytes and approved Parc mark
remain intact.

`scripts/test-capture-presentation.sh` checks source/backing-scale anchoring,
left/right and bottom alignment, real pixel-crop mapping and clipping, 30 compact
and tall-image layouts, separate appearance-state colors and original cursor
representations. Inert native renders inspect the production overlay in light,
dark, compact, crop, busy and empty-result states. They use a labeled generated
image, no renderer, no output-service invocation and no ordered app window.
The full app receives warnings-as-errors typecheck and final whole-module SIL.
These checks establish source/component behavior only; no functional browser
tests, runtime acceptance or pixel-matched whole-browser claim accompanies CAP18.
