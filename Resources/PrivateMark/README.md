# Private window artwork

`PrivateMark` is Parc's private-window mark, nicknamed Boo: a blushing sheet
ghost on a gradient drawn from the P's red and blue, with the P's blue foot
showing under the hem. It is a full-bleed square, with every shape inside the
central 80% so macOS can round and crop it.

- `PrivateMark.svg` is the vector drawing on a 1024 × 1024 canvas.
- `PrivateMark.png` is its 1024 × 1024 rendition.

macOS Now Playing shows it in place of a page's artwork while media plays in a
private window, which hides the page's own title and artwork there. The engine's
resource-bundle delegate loads it from the app bundle. See
[app icon marks](../../docs/app-icon-marks.md).
