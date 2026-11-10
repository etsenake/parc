# What's New page

`scripts/build.py` renders `WhatsNew.html` with `scripts/whats_new.py` from the
repository's `release-notes.json` and bundles the result as
`Contents/Resources/WhatsNew.html`. It's one self-contained file: the font, the
Parc mark, the grain texture and the favicon are inlined once each, and its
Content-Security-Policy allows no scripts or network loads.
A missing `release-notes.json` renders the empty state.

Preview it with the sample history:

```sh
python3 scripts/whats_new.py --notes tests/Packaging/fixtures/release-notes-sample.json build/whats-new/sample.html
```

## Where the design comes from

`PreferencesFeature.MaxBanner` clips `MaxBannerColor` (`#484FFF`) under a
`y = maxY − A + (A / 2) · sin(−2πx / 20)` across the width, so its wavelength
is always 20 pt. The CSS mask repeats one 20 × 6 pt period of that curve. The
to within a few colour levels. Over it, Parc's grain texture
(`Resources/ThemeTextures/grain.png`, the tile onboarding's import header and
setup card draw) repeats every 100 px with `overlay` blending at full
strength. The onboarding welcome's grain frames are 8 MB each, too heavy to
inline. The divider between releases reuses the wave as a line.

their italic lines in EB Garamond; Josh chose Cormorant over it and two other
open-licensed italics from rendered options. `CormorantGaramond-SemiBoldItalic.woff`
is a 21 KB Latin subset, at weight 600, of google/fonts'
`ofl/cormorantgaramond/CormorantGaramond-Italic[wght].ttf` (SHA256
`0f48ea6abb2084537854f7174c470991a463b13036309e3b50a81511611c530d`). Only the
page carries the font; its licence, `Resources/WhatsNew/OFL.txt`, ships in the
bundle:

```sh
python3 -m fontTools.varLib.instancer 'CormorantGaramond-Italic[wght].ttf' wght=600 --update-name-table -o semibold.ttf
python3 -m fontTools.subset semibold.ttf --unicodes='U+0020-007E,U+00A0-00FF,U+2013-2014,U+2018-201F,U+2022,U+2026' \
  --layout-features='kern,liga,calt,locl' --name-IDs='*' --flavor=woff --output-file=CormorantGaramond-SemiBoldItalic.woff
```

Paper `#FFFCEC`, ink `#100E22` and blue
highlight colours (`PreferencesSectionHighlight*`, `ARC_PreferencesFeature`
catalog). `mark.png` is Parc's `Resources/AppIcons/Marks/Monochrome.png` at twice the
size the page shows it.
`favicon.png` is `Marks/Borderless.png` centred in a 32 px square, since Chromium
stores favicons as square 16 and 32 px bitmaps:
`sips -Z 30 Borderless.png --out mark.png && sips -p 32 32 mark.png --out favicon.png`.
