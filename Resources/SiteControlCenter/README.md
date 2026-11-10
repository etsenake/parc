# Site Control Center artwork

`ARC_SiteControlCenter.bundle/Contents/Resources/Assets.car`. Parc bundles them
Company branding.

- `icon-control-center`: toolbar and address-pill entry glyph, 18 × 18 points.
- `copy-url`: Copy URL button, 19 × 19 points.
- `capture-full-page`: full-page capture button, 19 × 19 points.

Each name has `.png`, `@2x.png` and `.pdf` files. AppKit supplied the 1× and 2×
compiled bitmaps and ImageIO wrote them without resizing or redrawing, keeping
Generic Gray Gamma 2.2 color and alpha. Each PDF preserves the paths by drawing
the catalog's SVG representation once into a PDF context at the 1× point size;
the SVG payload itself is not stored.

`SiteControlCenterArtwork` combines both bitmaps and the vector at the 1× size
as a template. Share and Capture use the SF Symbols `square.and.arrow.up` and
`camera`. Visible Area uses the full-strength `photo.artframe` symbol; the
catalog's Portrait Mode image, `window-screenshot-icon`, is not bundled.

See [web interactions](../../docs/web-interactions.md) for Site Control Center
behavior. Asset provenance alone does not establish live appearance or motion.
