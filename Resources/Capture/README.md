# Capture cursor artwork and color provenance

1.170.0 (89123), `Contents/Resources/ARC_Capture.bundle/Contents/Resources/Assets.car`,
SHA-256 `f844669aa3e1da67309a194220cb1100f93d086791140f205428492af524a1a6`.
The installed catalog is used only to obtain the unavailable resource pixels and
named color values; behavior is traced once in the retained 1.122 executable.

The PDF is the catalog's unchanged raw vector payload (53.296878814697266 × 50
points). The PNGs are AppKit's original 53 × 50 and 107 × 100 compiled CGImage
renditions written by ImageIO without resizing or redrawing, in sRGB with alpha.
`CaptureArtwork` retains all three representations. The hotspot at (24, 25) is
application is required at build or runtime.

| File | SHA-256 |
|---|---|
| camera-cross-cursor.pdf | `34f4897bd049d211b020d397aa228d057e1360fc795b01d8564b068a8e234a1d` |
| camera-cross-cursor.png | `e4fd063eb91a1b56927bba0416f1ee1c3490813f876c7a617ef06009324f8e19` |
| camera-cross-cursor@2x.png | `d6354ef11a5e8e409bd285f392b0eed5a6ad64333c3430fc2303579ba38d61b4` |

`CaptureAppearance` copies the catalog's named light/dark color values:
Background, ImageViewBackground, TextColor, TextColorForSelectedCells,
TextFieldBackground, HoveredCellBackground,
HoveredAndKeyboardSelectedBackground, ToggleCellTextColor and OverlayBubbleText.
Display P3 colors retain that color space; remaining values use sRGB. The selected
`31176addd4f96f7ca0aa1a04743d64eba5ef429f4a89a723b62944a261e034b3`,
