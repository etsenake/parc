# Floating sidebar artwork

`CellDropShadow.png` and `CellDropShadow@2x.png` are the floating-sidebar shadow

The original renditions are 40 × 40 and 80 × 80 pixels, with Generic Gray
Gamma 2.2 color and alpha. AppKit supplied the images and ImageIO wrote them
without resizing. The stretchable image is a black ring around a clear,
10-point-radius hole, with a 10-point ramp up to 0.37 alpha. Cap insets are
19, 19, 20 and 20 points for top, left, bottom and right.

`FloatingSidebarSurface.shadowImage` in `ThemeRenderer.swift` combines both
bitmaps at the 1× point size with those cap insets. `scripts/build.py` copies
this directory to `Contents/Resources/FloatingSidebar`; the focused
`tests/FloatingSidebarSurface` checks cover packaging and resource integrity.
See [floating surface](../../docs/sidebar-motion.md#floating-surface) for how
the shadow fits the sidebar.
