# Parc UI marks and alpha cleanup

Parc's ten approved app-icon masters live in `Resources/AppIcons/<Variant>.png`.
They remain 1254 × 1254 RGBA images with the same catalog names and default.
The separate marks in `Resources/AppIcons/Marks` are UI resources, not additional
picker choices. [Icon sizing](app-icon-optical.md) covers native ICNS export.

## Production consumers

`ParcBrandMark` loads a borderless color image and a monochrome template.
The welcome animation and browser-import header use the color mark. The Safari
access illustration uses the full app tile because it represents the installed
application in System Settings. These images remain decorative beside text.

Portrait capture uses the monochrome alpha with its background-dependent ink.
The bowl and outside remain transparent; drawing preserves aspect ratio.
If the mark cannot load, the wordmark remains centered without an empty icon
slot. App, Dock and Finder icons continue using the selected tile artwork.
Packaging copies both marks with `Resources`; no runtime generation is needed.

## Asset preservation

Regenerate with `scripts/derive_app_icon_marks.py`, supplying the retained
approved originals and a distinct output directory. Review output and preservation
fingerprints before replacing assets. This deterministic tool preserves artwork;
do not redraw or generate replacement masters as routine maintenance.

The cleaned masters preserve every RGB byte, including hidden RGB, and every
pixel with alpha at least 128. Only low-alpha debris farther than two pixels from
the connected opaque body is cleared. Fingerprints and resulting hashes are in
`Resources/AppIcons/artwork-provenance.json`.

Both 560 × 828 marks derive from Original's colored P. The neutral tile, white
border and shadow are omitted by pixel chroma. Interior RGBA and proportions
remain unchanged; only the two-pixel antialias edge is unmatted from white.
The crop translates pixels without rescaling. Monochrome uses black RGB with
the color mark's exact alpha, allowing the consumer to provide its own ink.
Git retains the original approved input artwork.

## Checks

- `scripts/test-brand-marks.sh`: resource loading, matching alpha, missing-mark
  behavior and light/dark template drawing.
- `scripts/test-portrait-capture.sh`: the real portrait compositor and resources.
- `python3 -m unittest discover -s tests/BrandMarks -v`: approved-master RGB and
  protected-pixel fingerprints, alpha cleanup, contours and interior colors.
