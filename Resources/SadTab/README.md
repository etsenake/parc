# Crashed-page artwork

`ARC_SadTab.bundle/Contents/Resources/Assets.car`. The original rendition is
`sad_tab.svg`, at 96 × 103 points. Parc loads the standalone bundled files

- `SadTab.svg` preserves the catalog's vector payload after decompression.
- `SadTab.png` and `SadTab@2x.png` preserve its 96 × 103 and 192 × 206 compiled
  bitmaps. AppKit supplied the images and ImageIO wrote them without resizing
  or redrawing, keeping Generic Gray Gamma 2.2 color and alpha.

`SadTabContent.artwork` combines both bitmaps and the vector at the 1× point
size. Parc treats the result as a template and tints it with the source
branding. See [web interactions](../../docs/web-interactions.md) for crashed-page
behavior; asset provenance alone does not establish live appearance.
