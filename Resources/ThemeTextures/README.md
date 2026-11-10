# Theme renderer textures

`grain.png`, `sand.png`, `denim.png` and `tweed.png` come from the user-provided
`ARC_WindowThemeUI.bundle/Contents/Resources/Assets.car`. Their source asset
names are `grain_metal`, `sand_metal`, `denim_metal` and `tweed_metal`.

The native export loaded each `NSImage` by resource name and requested its
`CGImage` using the logical-size rectangle with no context or hints. This
selected a 200 × 200 pixel image for grain and 100 × 100 for the other textures.
ImageIO wrote those images without resizing or redrawing, preserving sRGB
profiles and alpha.

Parc's own renderer and shader load only these standalone PNGs. No original
provenance alone does not establish the complete renderer's appearance; see
[theme rendering](../../docs/space-theme-rendering.md).
