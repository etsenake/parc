# Theme editor assets

The theme editor's grid, texture knobs and appearance animations are Parc's
own artwork. Parc loads these standalone bundled resources; no other app,
executable code or asset catalog is involved.

## Grid and texture controls

`DotGrid.png`, `DenimKnob.png`, `GrainKnob.png`, `SandKnob.png` and
`TweedKnob.png` are Parc's own procedural artwork, drawn from fixed random
seeds and supersampled before downsampling.

DotGrid is template artwork at 799 × 801 pixels: 1.97-pixel dots on a 10-pixel
grid, drawn at the 2× scale of a 400 × 401-point canvas. Each knob is a
112 × 112-pixel swatch for a nominal 56-point control, drawn at 8× and box
filtered: half-transparent grey grain whose light falls off toward the lower
right; rounded matte pebbles of mixed size, each an irregular oval with its own
tone and soft top-left light, set in broken dark crevices; darker diagonal
denim threads interrupted by unevenly spaced bright vertical threads; and an
even tweed of short, randomly curling fibres over a faint mottle. The editor
clips each swatch to its control circle at 60% opacity. Keep layout dimensions
separate from pixel dimensions.

## Appearance animations

`sun.json`, `moon.json` and `automatic.json` are Parc's own Lottie animations
on a 500 × 500 canvas at 60 frames per second, built only from filled shape
layers with static paths and animated layer transforms. The sun's eight
short, rounded rays sit close to its disc and turn a full ray spacing every
second while the disc breathes; the
moon rocks and settles while two sparkles twinkle, then holds from frame 74;
the automatic icon is three twinkling sparkles. Selected appearance icons loop
and unselected icons pause. Parc's source renderer supports this subset.

## Color presets

`presets.json` contains 45 ordered picker records across five zero-based pages:
solid Brand, three-color analogous Brand, Pastel, Drab and Greyscale. The first
two pages intentionally reuse nine colors with different color counts and
harmony settings.

The nine Brand colors are Parc's own palette around its coral-red P: cream,
rose, plum, coral, vermilion, saffron, mint, sky and slate. Pastel tints each
Brand color toward white, Drab is a darker, muted counterpart of each, and
Greyscale steps from white to black. Every value is Display P3, and selecting
a named color keeps it in Display P3. See
[theme editor](../../docs/space-theme-editor.md) for interaction and animation
behavior.
