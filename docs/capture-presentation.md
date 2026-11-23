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
`CapturePictureView` sits on whole screen pixels and draws at the screen's own
resolution: pixel for pixel when the sizes match within two pixels, otherwise
through one high-quality resample. While the card lifts it stretches its current
rendering and redraws once it settles.

Small captures stay where they were taken. A capture whose source covers more
than half the page, such as Visible Area and Full Page, or that the palette
could not sit beside, is lifted into a card: the image fits the room left after
the palette column, a 16-point gap and margins of 8% of the page's shorter side
(24 points minimum), capped at 64% of the page width and 72% of its height, and
never larger than it was captured. The card and palette are centred together
with the palette on the card's right, top-aligned with it, so the dimmed page
shows on every side. Behind every preview the page gets Peek's wash: a copy of
the window's theme background at 70%, fading in over Peek's 0.3 seconds (at once
with Reduce Motion), in light and dark themes alike. Selection mode keeps its own
quarter-opacity scrim.

The preview card shares Peek's card values (`PeekCardAppearance`): 8-point
corners, its near-white or near-black fill showing as a four-point frame, its
hairline edge and soft 4-point shadow, with 4-point image corners inside. The palette is a 273-point Notes menu card (`CapturePaletteView`
on `NoteFloatingPanel` with `NoteMenuList` rows) with ten-point page margins and
image spacing. It prefers the image's right side when it fits, otherwise its
left, with top/bottom anchoring constrained by the page, and glides to its new
place when its height changes. It uses the Notes menu tokens: the Notes search
field, 34-point rows with Nunito titles and 20-point icon boxes, extra-bold
section headers, hairline dividers and the 12-point continuous card corners.
Easel and Note rows wear the Library's Easel and note marks, and their submenus
use 46-point detailed rows with an Edited subtitle.

Narrow split panes below twice the palette width plus 30 use separate image and
palette bands. The palette occupies at most 62% of available height and scrolls
its rows; the Frame page keeps its full height and the image band shrinks instead. The crop editor maps its clipped selection back to an
outward-rounded pixel rectangle; only `CapturedImage` commits the result.

The selection lens uses two live-page layers: grayscale/color blending and a
black quarter-opacity scrim with a shared cutout. Its focus expands six points;
its four-point frame is a light halo around a two-point Notes accent line, with
seven-point corners. An accent size chip sits under the frame's trailing corner,
or above or inside it when that would leave the page or cover the mode bar.

The mode bar is a Notes menu card (`CaptureModeBar` in a `NoteFloatingPanel`):
36 points high, 16 points above the page bottom, with 28-point Notes buttons
that pair an icon, a Nunito label and a keycap. The current mode uses the Notes
checked fill. Narrow panes drop the keycaps first, then the labels. The hint is
a slim Notes card in 12.5-point Nunito, eight points above the bar, or at the
bar's place when no bar is showing, such as crop and direct captures.
[Capture motion](capture-motion.md) owns transitions separately.

Appearance updates resolve native text and layer colors. Rows share one
highlight plate for the pointer and the keyboard, Saved to Library shows a
check, and unavailable rows draw at the Notes disabled opacity. Busy
Library/Messages states keep their callback gates and a status line at the
card's foot, which also carries errors; an empty search shows the Notes
no-results row. Starting capture/configuration clears
old outlines and image frames. Cancel and visible-area capture remain explicit
keyboard-accessible controls.

## Ownership and validation

`PageCaptureController.handleCaptureGesture(_:)` forwards to the original
`PageCaptureOverlay`. Geometry preserves freeform selection and opaque native
target tokens. The page, Profile, Space and physical-window leases remain with
the capture owner, as do current output bytes and the approved Parc mark.
Portrait composition, destination ordering, editing and motion have separate
focused guides.

`CapturePresentationTests` covers backing-scale anchoring, side and
bottom placement, lifted cards for visible-area, full-page, framed and large
captures, pixel-crop clipping, compact/tall layouts, appearance states and
cursor resources.
