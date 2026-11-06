# Parc UI marks and alpha cleanup

ICON08 owns the approved source artwork's outer alpha and the derived UI marks.
ICON09 owns optical sizing and native ICNS export in `scripts/app_icons.py`.
The interface is the existing ten `Resources/AppIcons/<Variant>.png` files:
1254 × 1254 RGBA, with the same names, approved design and catalog default.
ICON09 consumes the published cleaned masters without editing them. Marks live
separately in `Resources/AppIcons/Marks` and are not additional picker choices.

## Reference and adaptation

`4e452201e483b5480c0403a9ef8566e10515cdcb78828622ff9032b202e29547`.
These establish separate borderless resources, not the geometry of Parc's mark
or a recovered monochrome-tint algorithm. The existing onboarding reference and
portrait compositor contracts remain in [onboarding](onboarding.md#reference-and-adaptation)
and [page capture](page-capture.md#portrait-capture). No further decompilation was
needed to choose a separate bundled-mark resource boundary.

Parc's P, its monochrome silhouette and the choice to use that silhouette beside
branding is not bundled, loaded or recreated. `Original.png` remains the approved
master and app default; the terminal retains its approved 1-and-wink expression.

## Production consumers

`ParcBrandMark` loads the separate borderless color image and monochrome template.
The welcome animation and browser-import header use the color mark in their
existing image slots. Their animation, interaction and accessibility ownership
are unchanged; the images remain decorative beside existing explanatory text.
The Safari System Settings illustration still uses the full app tile because it
represents the installed application in that system list.

Portrait capture uses the monochrome mark's actual alpha and the existing
background-dependent ink color. Its bowl and outside area remain transparent.
The drawing helper preserves aspect ratio and works directly in the export's
CGContext. If the resource is unavailable, the remaining Parc wordmark is still
centered; a missing mark does not leave an empty reserved icon slot. This is a
resource-failure fallback, not an additional user choice.

The production packager already copies the entire `Resources` tree, so both
runtime generation step. The app/Dock/Finder icon controller and its persisted
ten-variant selection continue to use the tile artwork.

## Asset preservation and current work

Every approved master was visually inspected before modification. Its approved
central design is retained, including the original P's small left-facing terminal,
long narrow stem and inward curl turning right. Read-only analysis recorded all
ten original RGB hashes and alpha bounds before editing. Outer debris on the
inspected originals is below alpha 128; the main opaque tile/mascot remains a
coherent silhouette.

A constrained imagegen extraction was rejected: its colored-symbol bounds grew
from approximately x365–905/y230–1038 to x312–970/y194–1124 on the square canvas,
altering the approved proportions, and stray alpha speckles remained. That
candidate is not a production input. Josh then explicitly directed: **“Use
deterministic processing; preserve the artwork.”** The accepted output uses
`scripts/derive_app_icon_marks.py` with Pillow, without an image-generation service.

The ten cleaned masters retain their original 1254 × 1254 dimensions and every
RGB byte, including hidden RGB beneath fully transparent pixels. Every original
pixel whose alpha is at least 128 remains unchanged. Only low-alpha debris
farther than two pixels from the connected opaque body is cleared: 248,811 pixels
across the ten masters. Their original RGB and protected opaque-pixel SHA256
fingerprints and the resulting file hashes are in
`Resources/AppIcons/artwork-provenance.json`.

Both 560 × 828 marks derive directly from Original's colored P. The neutral tile,
white border and shadow are omitted using the original pixel chroma; its interior
RGBA values and proportions are unchanged. Only the two-pixel antialias transition
is unmatted from white. The recorded source crop is a translation, not rescaling
or redrawing. Monochrome uses black RGB with exactly the color mark's alpha. A
native image template supplies the actual foreground color at the consumer.

For a maintenance regeneration, pass the retained approved originals as the
first directory and a distinct output directory as the second. Review the
outputs and preservation fingerprints before replacing checked-in files. This
tool is not run by the application or packager. The source Git history retains
the original input artwork; raw candidates and inspection composites remain
outside Git under `work/icon08-artwork-evidence`.

## Checks

`scripts/test-brand-marks.sh` is an inert AppKit resource/drawing check: both
packaged resources, color/template alpha identity, missing-resource behavior,
and monochrome light/dark drawing without a tile or leaked original colors.
`scripts/test-portrait-capture.sh` exercises the real portrait compositor with
these same bundled resources. Neither script opens a browser or changes Dock,
Finder, user profiles, clipboard or system preferences. Final asset/check
receipts are recorded with the completed delivery in the parity ledger.
`python3 -m unittest discover -s tests/BrandMarks -v` additionally checks the
approved master RGB/protected-pixel fingerprints, absence of outlying alpha,
matching mark silhouettes, open bowl/curl landmarks and copied interior colors.
