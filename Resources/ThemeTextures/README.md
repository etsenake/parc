# Theme renderer textures

`grain.png`, `sand.png`, `denim.png` and `tweed.png` are Parc's own surface
textures, generated from fixed random seeds:

- `grain.png`: 200 × 200 straight-alpha colour noise at alpha 66. Each channel
  is independent noise shaped to a fine, slightly soft grain, with a light,
  bright-leaning tone so the theme colour stays clean.
- `sand.png`: 100 × 100 opaque grayscale noise with small bright specks and a
  bright-leaning spread.
- `denim.png`: 100 × 100 opaque weave built from a fine diagonal ripple and
  two sets of vertical threads at Parc's own offsets, with random per-thread
  brightness and fine noise.
- `tweed.png`: 100 × 100 opaque fibre noise with faint vertical thread bands.

Every tile is synthesised in the frequency domain, so it wraps at its edges
without a seam. The theme renderer, setup card, start page and What's New page
load these bundled PNGs. See
[theme rendering](../../docs/space-theme-rendering.md).
