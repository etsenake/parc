# Parc UI marks and alpha cleanup

Parc's ten approved app-icon masters live in `Resources/AppIcons/<Variant>.png`.
They remain 1254 × 1254 RGBA images with the same catalog names and default.
The separate marks in `Resources/AppIcons/Marks` are UI resources, not additional
picker choices; `Monochrome.svg` is the vector the engine draws. [Icon sizing](app-icon-optical.md) covers native ICNS export.

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

## Parc's mark on Chromium's pages

Chromium's own pages that Parc opens show Parc's P, never Chromium's logo:

- Page headers and narrow-window drawers (Settings, Extensions, History,
  Downloads, Bookmarks) show a black P in light mode and a white P in dark mode.
- Settings → About Parc does the same at its larger size, and the version page
  shows the P in both modes.
- The About Parc row in Settings' sidebar, Safety Hub's browser row and the
  certificate manager's sidebar draw the P as an icon in the row's own colour.
- The favicons Chromium keeps for the version and What's New pages are the black P.
- The first-run, profile picker, search engine choice and default browser pages
  show a P that turns white in dark mode.

Every one comes from `Marks/Monochrome.svg`, a trace of `Monochrome.png` in the
24-unit icon box, 20 units tall and centred as the PNG is drawn. The same path is
compiled into [the branding rules](../Engine/ParcChromium/webui_branding_rules.h).
The logos, favicons and dark-mode images replace Chromium's files outright and
never load an image file, so they can't fall back to Chromium's artwork.

Chromium loads a page's scripts, styles and images in the page's own renderer
from that process's resource bundle; only the page document comes from the
browser. So both resource-bundle delegates apply the same rules from
[`webui_branding.cc`](../Engine/ParcChromium/webui_branding.cc), and the browser
draws the `chrome://theme` logos and favicons from the vector at whatever scale a
page asks for. The page icons, the About layout and the version and
metrics-internals wording are text rules inside Chromium's pages: each names
exactly what it replaces and how many times it must appear, and one that no
longer matches is skipped and logged, never half applied, leaving Chromium's
original. So a Chromium upgrade runs `tests/WebUIBranding/check.py` against the
rebuilt copy, which fails on any changed text or count
([upgrading Chromium](../Engine/README.md#upgrading-chromium)).

The task manager's Browser row still shows Chromium's small colour logo: a
one-colour P would disappear on its dark table, so it waits for a colour vector.

## Asset preservation

The marks and cleaned masters were produced once by a deterministic process
that preserves the artwork; do not redraw or regenerate them as routine
maintenance.

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

- `BrandMarkTests`: resource loading, missing-mark behavior and light/dark
  template drawing.
- `scripts/test-portrait-capture.sh`: the real portrait compositor and resources.
- `python3 -m unittest discover -s tests/BrandMarks -v`: approved-master RGB and
  protected-pixel fingerprints, alpha cleanup, contours and interior colors.
- `python3 tests/WebUIBranding/check.py`: the engine's vector against
  `Monochrome.svg`, the branding rules and, with an engine workspace, every
  Chromium text and page they rely on ([details](../tests/WebUIBranding/README.md)).
