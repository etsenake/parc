# Library artwork

## Library entry and download placeholder

The Library entry combines five Parc template layers: `box` (a bucket with a
short handle slot), `star`, `triangle`, `circle` and `glow` (a soft beam shown
only on hover in dark mode). Each layer has a vector `.pdf` plus `.png` and
`@2x.png` renditions rendered from the same geometry with 8× supersampling; the
glow's PDF is a banded opacity gradient.

`EmptyFavicon` is the Downloads placeholder: a rounded square at 72/255 template
alpha, as `EmptyFavicon.svg` plus 1× and 2× PNGs.

`LibraryArtwork` combines these representations as templates at their point
sizes: box 12 × 9, star 9 × 9, triangle 3.5 × 3 (4 × 3 pixels at 1×), circle
2 × 2, glow 81 × 27 and EmptyFavicon 14 × 14. See
[downloads](../../docs/download-library.md) for the placeholder's consumer.

## Easel and Note title cards

`note.png` is Parc's P mark (`Resources/AppIcons/Marks/Monochrome.png`) with a
cursor bar; `easel.png` is a paintbrush laying a stroke. Both are coral, with
lighter `-dark` variants, at 18 and 36 pixels for the 18-point card artwork.
They were drawn for Parc as vectors and rendered with 8x supersampling. These are colored
images, not templates. See [documents Library](../../docs/documents-library-grid.md)
for their use.

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

The renderer draws the stored shape paths without the 12 Offset Path modifiers
in `easels`, `spaces` and `archive`. Those modifiers specify a −0.5-unit inset
with miter joins.
