# Library artwork

## Library entry and download placeholder

The Library entry combines five Parc template layers: `box` (a bucket with a
short handle slot), `star`, `triangle`, `circle` and `glow` (a soft beam shown
only on hover in dark mode). Each layer has a vector `.pdf` plus `.png` and
`@2x.png` renditions rendered from the same geometry with 8× supersampling; the
glow's PDF is a banded opacity gradient, nearly clear at its wide top and
strongest at its narrow base so the beam rises from the box.

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
`archive.json` are Parc's own Lottie compositions on a 128 × 128 canvas at 60
frames per second: two photo cards, a download ring and arrow, an easel canvas
with the Easel card's paintbrush and stroke, two Space cards, and an archive box
with a lid. Each selection is a spring: the icon squashes and winds up through
`hover-end`, launches with a stretch and hop on an overshooting curve, swings
past rest and settles exactly back on its first frame by `selection-end`. The
photo cards press together and fan out, the arrow lifts then drops and bounces,
the paintbrush winds back and sweeps its stroke on again, the front Space card
swings wide against the back one, and the lid flies up and lands with a bounce.
Each uses only shape layers, nested parenting, transforms, path strokes and
fills, and carries the `hover-start` (1), `hover-end` (11) and `selection-end`
(35) markers.

`LibraryRailAnimation` renders the files directly; Parc does not bundle a
Lottie runtime. It colors `primaryColor` and `secondaryColor` layers with the
theme's `maxContrastColor` and `cutoutColor`. Selection plays `hover-start` to
`selection-end` once unless Reduce Motion is on, at 60 percent of the
composition's pace, so the wind-up takes about a quarter second and the whole
hop a little under one. Deselection does not interrupt a hop, and selecting the
tile again mid-hop lets it carry on rather than jump back to the start.
Completion parks on `selection-end`, which matches frame 0 (`ip`), the pose an
unplayed page shows. `LibraryRailMotion` owns these timings and the tile's
fades; see [the rail's motion](../../docs/download-library.md#search-filter-and-layout).
