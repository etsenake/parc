# App icon optical export

ICON09 owns the native icon export framing and small-size inspection. ICON08
owns the ten approved master PNGs, alpha cleanup and derived UI marks. The
exporter consumes those masters without changing their pixels on disk. The
approved Original geometry and Dev's numeral, wink and pedestal remain intact.

Josh explicitly authorized this method on October 28: **“Use deterministic
processing; preserve the artwork.”** The native affine export below follows
that direction; it does not regenerate or redraw any approved artwork.

## Retained reference and adaptation

The original icon-generation reference set lives at
`outputs/parc-icon-family/references` in the shared reference workspace. Its
family provenance is retained in `Resources/AppIcons/README.md`. No new binary
trace or reference-version comparison is necessary for this raster question.

Measuring pixels with alpha at least 128 gives `[100, 100, 924, 924)` for eight
1024-pixel square treatments and `[50, 50, 462, 462)` for the 512-pixel Hologram.
All nine therefore use the same centered **824 / 1024** opaque envelope. The
256-pixel Dev reference has `[30, 28, 226, 232)`: its largest extent is
**204 / 256** and its vertical center is **130 / 256**. These are asset
used by Parc at build or runtime.

Before correction, the approved Parc PNGs' dominant opaque extents range from
1042 to 1114 pixels on a 1254-pixel canvas, with slight center offsets. The
export adapts the retained reference envelope to the approved P artwork:

- Measure the master's alpha-at-least-128 bounds so faint shadows cannot
  enlarge the optical body.
- Uniformly scale the whole source to the reference's dominant extent and
  center it. Preserve the source aspect ratio instead of stretching tile or
  mascot proportions to match the reference silhouette.
- Round the dominant extent and placement for each native pixel size. The
  16-pixel representation has a 13-pixel dominant body; the 32-pixel one has 26.
  Each 1x/2x representation is rendered directly from the full master.
- Use native Core Image Lanczos downsampling in premultiplied sRGB on a
  transparent canvas, with software rendering for repeatable output. A
  transparent outer pixel ring removes the filter's resampling fringe at tiny
  sizes without intersecting the opaque body. No sharpen filter, new outline,
  color substitution or glyph redraw is applied.

This is a Parc export adaptation. The P and terminal artwork stay distinct

## Production boundary

`scripts/app_icons.py` compiles the small offline
`scripts/render_app_icon.swift` renderer once per family export, using the
existing Xcode build dependency. The helper emits the ten standard PNG
representations. Apple's `iconutil` packages each `AppIcons/<Variant>.icns`;
`Original.icns` remains the main and Alerts helper default in all configurations.

ICON11 owns the controller-side integration: packaged ICNS is used when
present, PNG fallback is for source-only previews when no ICNS exists, and a
present damaged ICNS is an availability error. This ensures live Dock/Finder
identity and the Settings preview receive the same native family already used
by the non-running Dock plugin. ICON10 owns picker interaction without adding
another crop or normalization layer.

## Checks and appearance evidence

The focused AppIcons check round-trips all ten variants through `iconutil` and
decodes all 100 output PNGs independently using Python's standard library. It
checks representation dimensions, reference-derived opaque extent and center,
transparent outer pixel rings, distinct variant exports, unchanged masters and
Original as the shared default. `tests/Packaging/test_icons.py` also exercises
the production resource path in both configurations with real native export;
its application compiler, browser engine and signing operations are isolated
test doubles; the icon renderer is compiled and executed normally.

The finished deterministic exporter passed all 100 representation checks on
ICON08's cleaned-master candidate. All ten production packaging cases pass,
including both configurations' identical variant bytes and main/Alerts default
identity. All 80 inert production-controller assertions pass with these new
ICNS files, including native representation loading and the actual injected
live-image consumer. They also compare the actual premultiplied pixels of native
representations with equal pixel dimensions, independent of logical 1x/2x size.
The standalone renderer's warnings-as-errors SIL check
passes. These checks do not load or launch a browser, change a real preference,
or apply an icon to the user's Dock/Finder.

The actual 16-, 32-, 64- and 128-pixel exported PNGs and native ICNS
representations for all ten variants were inspected on light and dark
backgrounds. The P terminal/curl is retained;
Fluted Glass's texture reduces without losing the colored P; Hologram and Neon
retain their thin outline treatment; Dev retains the numeral, wink and pedestal.
The master artwork's fine detail naturally reduces at 16 pixels. This is an
inspection of the exported pixels, not an integrated Dock/Finder screenshot or
the separate whole-product polish pass.

Local output, source hashes, review and check receipts are retained in
`work/app-icons-checks/icon09`, outside Git; `native-small-sizes.png` is the
actual-size light/dark native contact sheet. Final master publication is reconciled by
hash against that inspected candidate before row completion. All ten master
SHA-256 values from ICON08's published `8a0f074b` match the inspected/check input
exactly; ICON10's `5bbd3101` keeps the recovered 64-point proportional preview,
and ICON11's `5b752538` supplies the shared native-image loader.

Fresh independent `icon09_optical/icon09_review` cleared the complete exporter,
native helper, test changes and documentation with no actionable findings. Its
source hashes and confirmation are retained in `review-clearance.md`. ICON09
completes the eleven-row App identity family under the implementation rule;
whole-product polish remains separately tracked.
