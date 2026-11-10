# Theme editor assets

(71105) reference. Parc loads standalone bundled resources without an installed

## Grid and texture controls

`DotGrid.png`, `DenimKnob.png`, `GrainKnob.png`, `SandKnob.png` and
`TweedKnob.png` come from `ARC_SpaceStyleEditor.bundle/Contents/Resources/Assets.car`.
AppKit selected the native 2× bitmaps and ImageIO wrote them without resizing or
redrawing, preserving their embedded color profiles and alpha.

DotGrid is template artwork at 799 × 801 pixels, with an original logical size
of 400 × 401. Each knob is 112 × 112 pixels with a nominal 56-point size;
the source GrainKnob reports 56 × 57. Keep native layout dimensions separate
from pixel dimensions.

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
