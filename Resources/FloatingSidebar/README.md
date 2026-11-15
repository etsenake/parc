# Floating sidebar artwork

`CellDropShadow.png` and `CellDropShadow@2x.png` are the soft shadow drawn
around the floating sidebar. Parc drew them for this project at 40 × 40 and
80 × 80 pixels: black with alpha, a clear 20-point hole with the surface's
8-point corner radius, and a Gaussian falloff from about 0.39 alpha at the
hole's edge to nothing 10 points out. Cap insets are 19, 19, 20 and 20 points
for top, left, bottom and right, so only the clear middle stretches.

`FloatingSidebarSurface.shadowImage` in `ThemeRenderer.swift` combines both
bitmaps at the 1× point size with those cap insets and draws the result at 20%
opacity. `scripts/build.py` copies this directory to
`Contents/Resources/FloatingSidebar`; the focused `tests/FloatingSidebarSurface`
checks cover packaging and resource integrity. See
[floating surface](../../docs/sidebar-motion.md#floating-surface) for how the
shadow fits the sidebar.
