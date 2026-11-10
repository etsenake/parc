# Library artwork


## Library entry and download placeholder

The Library entry combines five layers from
`circle` and `glow`. Their source renditions use the same names with `.pdf`,
except `glow`, whose original name is `Rectangle 14.pdf`.

`EmptyFavicon` is the Downloads placeholder from
`EmptyFavicon.svg`. Its two layers, with fill opacity 0.1 over 0.2, combine to
72/255 template alpha.

Each layer has a vector (`.pdf` or `.svg`) and 1×/2× bitmap (`.png` and
`@2x.png`) representation. Vectors preserve the catalog payload after any
required decompression. AppKit supplied the compiled bitmaps and ImageIO wrote
them without resizing or redrawing, preserving alpha and color profiles:
Generic Gray Gamma 2.2 for the layers, sRGB for EmptyFavicon.

`LibraryArtwork` combines these representations as templates at their original
point sizes: box 12 × 9, star 9 × 9, triangle 4 × 3, circle 2 × 2, glow 81 × 27
and EmptyFavicon 14 × 14. See [downloads](../../docs/download-library.md) for
the placeholder's consumer.

## Easel and Note title cards

`easel.png`, `note.png`, their `-dark` variants and their `@2x.png` versions
come from `ARC_HomeButton.bundle/Contents/Resources/Assets.car`. The original
asset names are `icon-home-easel.svg`, `icon-home-easel-dark.svg`,
`icon-home-notes.svg` and `icon-home-notes-dark.svg`.

The 18 × 18 and 36 × 36 compiled representations were exported through AppKit
and ImageIO without resampling, using Aqua and Dark Aqua to select the matching
appearance. These are colored images, not templates. See
[documents Library](../../docs/documents-library-grid.md) for their use.

## Animated rail icons

`screenshots.json`, `downloads.json`, `easels.json`, `spaces.json` and
`archive.json` are unchanged Lottie compositions from the same HomeButton bundle.
`boosts.json` is not included because Boosts are excluded.

`LibraryRailAnimation` renders the files directly; Parc does not bundle a
Lottie runtime. It colors `primaryColor` and `secondaryColor` layers with the
theme's `maxContrastColor` and `cutoutColor`. Selection plays `hover-start` to
`selection-end` once unless Reduce Motion is on. Deselection does not interrupt
an animation. Completion parks on `selection-end`; an unplayed page shows
frame 0 (`ip`).

The renderer skips the 12 Offset Path items in `easels`, `spaces` and `archive`.
renderer also ignores them has not been confirmed by tracing actual rendering.
If it applies them, Parc's affected icon edges would be about 0.1 point fuller
at a 28-point display size. Resource provenance does not settle that appearance
question; it remains a presentation-validation boundary.
