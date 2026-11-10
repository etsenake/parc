# App icon optical export

Parc exports ten approved master PNGs into native ICNS representations without
redrawing or modifying the masters. Preserve Original's geometry and Dev's
numeral, wink and pedestal. Artwork provenance belongs in
[the resource guide](../Resources/AppIcons/README.md).

## Production boundary

`scripts/app_icons.py` compiles `scripts/render_app_icon.swift` once per family
export. The helper renders the ten standard PNG representations and `iconutil`
packages each `AppIcons/<Variant>.icns`. `Original.icns` is the application and
Alerts helper default in every configuration. Xcode supplies the native renderer;
there is no additional Python package or external application dependency.

The exporter measures alpha-at-least-128 bounds so faint shadows do not enlarge
the optical body. It uniformly scales the complete source, preserves aspect
ratio and centers it on a transparent canvas. Standard variants use a dominant
824/1024 extent; Dev uses 204/256 with vertical center 130/256. Extent and
placement are rounded at each output size: the standard 16- and 32-pixel
representations have 13- and 26-pixel dominant bodies.

Each representation comes directly from the full master through Core Image
Lanczos downsampling in premultiplied sRGB with software rendering. A transparent
outer pixel ring removes resampling fringe at tiny sizes. No sharpening, new
outline, color substitution or glyph redraw is applied.

The controller uses a packaged ICNS when present. PNG fallback is available for
source-only previews without an ICNS; a present but damaged ICNS is an
availability error. Settings previews and native application identity therefore
consume the same export without an additional crop or normalization step.

## Checks and appearance evidence

The AppIcons checks round-trip all variants through `iconutil` and independently
decode their PNG representations. They cover dimensions, opaque extent/center,
transparent outer rings, distinct variants, unchanged masters and the shared
default. `tests/Packaging/test_icons.py` covers the real resource export in both
configurations while isolating app compilation, engine and signing operations.
Controller checks cover native loading and equality of representations with the
same pixel dimensions but different logical scale.

Exported-pixel inspection and compiler/component results do not establish live
Dock/Finder behavior or whole-product visual acceptance. Fine master detail
naturally reduces at 16 pixels.
