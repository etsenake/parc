# Crashed-page artwork

`SadTab` is Parc's crashed-page template image: a flower wilting in its pot,
drawn in rounded 8.5-point strokes on a 96 × 103-point canvas.

- `SadTab.svg` is the vector drawing.
- `SadTab.png` and `SadTab@2x.png` are its 96 × 103 and 192 × 206 renditions,
  rendered from the same geometry with 8× supersampling.

`SadTabContent.artwork` combines both bitmaps and the vector at the 1× point
size. Parc treats the result as a template and tints it with the source
`ForegroundTertiary` color. See [web interactions](../../docs/web-interactions.md)
for crashed-page behavior.
