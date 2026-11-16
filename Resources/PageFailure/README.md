# Page failure artwork

`PageFailure` is the drawing on Parc's "This page couldn’t open" view: the
paper plane nose-down in the ground from Parc's network error pages, drawn in
the same rounded strokes as the crashed-page flower.

- `PageFailure.svg` is the vector drawing, framed to the plane's full extent.
- `PageFailure.png` and `PageFailure@2x.png` are its 96 × 96 and 192 × 192
  renditions, rendered from the same geometry with 8× supersampling.

`SadTabContent.navigationArtwork` combines both bitmaps and the vector at the
1× point size as a template, tinted like the crashed-page flower. See
[web interactions](../../docs/web-interactions.md#failure-and-recovery-surfaces--web17)
for when the view appears.
