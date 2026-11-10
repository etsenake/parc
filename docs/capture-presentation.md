# Capture selection and output presentation

The selection surface, captured image, crop editor and output palette share
`CapturePresentation` geometry. They display the original page owner's immutable
PNG; drawing never recaptures pixels or changes destination identity.

## Geometry and states

The preview retains the logical source rectangle used to request pixels. Region
captures map the native rectangle; element captures include its two-point
expansion and clipping. Viewport/full-page requests retain their original
viewport. Pixels fit without distortion. Crop and Portrait changes fit the new
aspect ratio in that same context without resampling the retained source PNG.

The preview uses a four-point frame, seven-point outer corners and 3.5-point
image corners. The normal palette is 273 points wide with ten-point page margins
and image spacing. It prefers the image's right side when it fits, otherwise
its left, with top/bottom anchoring constrained by the page. Rows are 32 points
high, with 14-point medium labels, seven-point horizontal padding and six-point
corners. The search field is 30 points high with 13-point medium text.

Narrow split panes below twice the palette width plus 30 use separate image and
palette bands. The palette occupies at most 62% of available height and scrolls
its genuine actions. The crop editor maps its clipped selection back to an
outward-rounded pixel rectangle; only `CapturedImage` commits the result.

The selection lens uses two live-page layers: grayscale/color blending and a
black quarter-opacity scrim with a shared cutout. Its focus expands six points;
it has a four-point border and seven-point corners. The instruction card uses
14-point semibold text, 25-point padding, 16-point corners and a static gradient.
[Capture motion](capture-motion.md) owns transitions separately.

Appearance updates resolve native text and layer colors. Idle, hover, keyboard
selection, combined selection, saved-toggle and disabled rows have distinct ink.
Busy Library/Messages states retain callback gates and status text; an empty
search retains its empty-result surface. Starting capture/configuration clears
old outlines and image frames. Cancel and visible-area capture remain explicit
keyboard-accessible controls.

## Ownership and validation

`PageCaptureController.handleCaptureGesture(_:)` forwards to the original
`PageCaptureOverlay`. Geometry preserves freeform selection and opaque native
target tokens. The page, Profile, Space and physical-window leases remain with
the capture owner, as do current output bytes and the approved Parc mark.
Portrait composition, destination ordering, editing and motion have separate
focused guides.

`scripts/test-capture-presentation.sh` covers backing-scale anchoring, side and
bottom placement, pixel-crop clipping, compact/tall layouts, appearance states
and cursor resources. These inert checks and compiler validation do not establish
browser-runtime acceptance or live rendering equivalence.
