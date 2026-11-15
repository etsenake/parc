# Theme editor assets

(71105) reference. Parc loads standalone bundled resources without an installed

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

`sun.json`, `moon.json` and `automatic.json` are unchanged Lottie files from
the same bundle. Selected appearance icons loop and unselected icons pause.
Parc's source renderer supports the animation subset these files use.

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
