# Navigation control artwork

`icon-browser-navigation-force-reload` is the force-refresh template image from
named `hard refresh.pdf`. Parc loads standalone bundled files without an

- `icon-browser-navigation-force-reload.pdf` preserves the vector rendition
  from AppKit's `NSPDFImageRep` at 22 × 15 points.
- `icon-browser-navigation-force-reload.png` and
  `icon-browser-navigation-force-reload@2x.png` preserve the 22 × 15 and
  44 × 30 compiled bitmaps, including Generic Gray Gamma 2.2 color and alpha.
  ImageIO wrote the native images without resizing.

`NavigationControlArtwork` combines the two bitmaps and vector at the 1× point
button's behavior.
