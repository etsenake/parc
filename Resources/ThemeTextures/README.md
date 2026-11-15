# Theme renderer textures

`grain.png`, `sand.png`, `denim.png` and `tweed.png` are Parc's own procedural
surface textures, generated from fixed random seeds:

- `grain.png`: 200 × 200 straight-alpha colour noise at alpha 66, softened by a
  wrapped three-tap kernel so the 100-point tile repeats without a seam.
- `sand.png`: 100 × 100 opaque grayscale noise with a bright-leaning spread.
- `denim.png`: 100 × 100 opaque 3/1 twill with per-thread variation.
- `tweed.png`: 100 × 100 opaque fleck noise over a soft mottle, faint vertical
  thread bands and a three-pixel weave.

Each tile wraps at its edges. The theme renderer, setup card, start page and
What's New page load these bundled PNGs. See
[theme rendering](../../docs/space-theme-rendering.md).
