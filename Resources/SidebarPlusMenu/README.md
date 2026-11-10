# Sidebar plus menu artwork

`add-space`, `split-add-right` and `add-tab` are the New Space, New Split and
`ARC_SidebarPlusButton.bundle/Contents/Resources/Assets.car`, whose original
renditions are named `new-menu-add-space.pdf`,
`new-menu-add-split--horizontal.pdf` and `new-menu-new-tab.pdf`.

Each asset has a `.pdf`, `.png` and `@2x.png` file in this directory. The PDFs
preserve AppKit's vector rendition at 28 × 28 points. The bitmaps preserve the
28 × 28 and 56 × 56 compiled renditions, gray color profile and alpha;
ImageIO wrote them without resizing.

`SidebarPlusMenuArtwork` combines each vector and pair of bitmaps at the 1×
point size as a template. The menu draws the result in a 24-point frame. Parc
The catalog's colored `boost`, `easel`, `folder`, `note`, `space` and `tab`
images and excluded `boost_legacy` image are not included.

See [sidebar motion](../../docs/sidebar-motion.md#dock-plus-hud) for the menu's
presentation and interaction.
