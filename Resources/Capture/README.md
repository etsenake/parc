# Capture cursor artwork and colors

`camera-cross-cursor` is the pointer shown while choosing an area to capture:
a rounded crosshair on the click point with a small camera badge above and to
the right. Parc drew it for this project; both shapes carry a white outline and
a soft shadow so the pointer reads on light and dark pages.

- `camera-cross-cursor.pdf` is the vector original, about 53.3 × 50 points,
  so the pointer stays sharp when macOS enlarges it for accessibility.
- `camera-cross-cursor.png` and `camera-cross-cursor@2x.png` are 53 × 50 and
  107 × 100 renderings of the same drawing in sRGB with alpha.
- `CaptureArtwork` loads all three representations. Its hotspot at (24, 25)
  places the cross center at the pointer.

`CaptureAppearance` defines the capture panel's light and dark colors in code:
background, image backdrop, text, selected text, field, hover and selection
states, the toggle tint and the overlay hint. Display P3 colors keep that color
space; the rest use sRGB.

Build and runtime load only these bundled files. See
[page capture](../../docs/page-capture.md) for behavior and ownership.
