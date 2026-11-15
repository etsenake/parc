# Sidebar plus menu artwork

`add-space`, `split-add-right` and `add-tab` are Parc's New Space, New Split and
New Tab template images: a pair of stacked cards, a card split into two equal
halves with a plus breaking through its right edge, and a single card with a
plus, drawn on a 28-point canvas with 2.2-point strokes.

Each has a vector `.pdf` plus `.png` and `@2x.png` renditions at 28 × 28 and
56 × 56 pixels, rendered from the same geometry with 8× supersampling.
`SidebarPlusMenuArtwork` combines them at the 1× point size as a template, and
the menu draws the result in a 24-point frame. The remaining rows use SF Symbols.

See [sidebar motion](../../docs/sidebar-motion.md#dock-plus-hud) for the menu's
presentation and interaction.
