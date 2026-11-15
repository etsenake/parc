# Theme editor assets

The theme editor's grid, texture knobs and appearance animations are Parc's
own artwork. Parc loads these standalone bundled resources; no other app,
executable code or asset catalog is involved.

## Grid and texture controls

`DotGrid.png`, `DenimKnob.png`, `GrainKnob.png`, `SandKnob.png` and
`TweedKnob.png` are Parc's own procedural artwork, drawn from fixed random
seeds and supersampled before downsampling.

DotGrid is template artwork at 799 × 801 pixels: 2.2-pixel dots on a 10-pixel
grid, drawn at the 2× scale of a 400 × 401-point canvas. Each knob is a
112 × 112-pixel swatch for a nominal 56-point control: a steep 3/1 denim
twill with thread shading, translucent grey grain fading darker toward the
bottom, sand pebbles with lit faces and dark gaps, and a tweed of short curved
fibres. Keep layout dimensions separate from pixel dimensions.

## Appearance animations

`sun.json`, `moon.json` and `automatic.json` are Parc's own Lottie animations
on a 500 × 500 canvas at 60 frames per second, built only from filled shape
layers with static paths and animated layer transforms. The sun's eight
rounded rays turn a full ray spacing every second while its disc breathes; the
moon rocks and settles while two sparkles twinkle, then holds from frame 74;
the automatic icon is three twinkling sparkles. Selected appearance icons loop
and unselected icons pause. Parc's source renderer supports this subset.

## Color presets

`presets.json` contains 45 ordered picker records across five zero-based pages:
solid Brand, three-color analogous Brand, Pastel, Drab and Greyscale. The first
two pages intentionally reuse nine colors with different color counts and
harmony settings.

the remaining families come from the editor catalog. Floating-point RGBA values
are preserved. Brand1–4 use sRGB; Brand5 uses extended linear sRGB (`linearSRGB`
in the loader); Brand6–9 and every Pastel, Drab and Greyscale color use Display
P3. Selecting a named color converts it to Display P3.

Extraction used semantic asset names, since internal rendition filenames can
be reused. See [theme editor](../../docs/space-theme-editor.md) for interaction
and animation behavior.
