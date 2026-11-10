# Capture cursor artwork and colors

exported from `ARC_Capture.bundle/Contents/Resources/Assets.car`. Parc bundles
these standalone resources and owns the behavior that uses them.

- `camera-cross-cursor.pdf` preserves the original vector at approximately
  53.3 × 50 points.
- `camera-cross-cursor.png` and `camera-cross-cursor@2x.png` preserve the
  catalog's 53 × 50 and 107 × 100 compiled bitmaps in sRGB with alpha.
  AppKit supplied the images and ImageIO wrote them without resizing or redrawing.
- `CaptureArtwork` retains all three representations. Its hotspot at (24, 25)
  places the native cursor's cross center at the pointer.

`CaptureAppearance` uses the catalog's named light/dark colors: Background,
ImageViewBackground, TextColor, TextColorForSelectedCells, TextFieldBackground,
HoveredCellBackground, HoveredAndKeyboardSelectedBackground, ToggleCellTextColor
and OverlayBubbleText. Display P3 colors retain that color space; remaining
values use sRGB. The selected row's BrandBlue comes from

and runtime load only Parc's bundled files. See [page capture](../../docs/page-capture.md)
for behavior and ownership.
