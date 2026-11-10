# What's New page

`scripts/build.py` renders `WhatsNew.html` with `scripts/whats_new.py` from the
repository's `release-notes.json` and bundles the result as
`Contents/Resources/WhatsNew.html`. It's one self-contained file: the font, the
Parc mark and the favicon are inlined, and its Content-Security-Policy allows
no scripts or network loads.
A missing `release-notes.json` renders the empty state.

Preview it with the sample history:

```sh
python3 scripts/whats_new.py --notes tests/Packaging/fixtures/release-notes-sample.json build/whats-new/sample.html
```

## Where the design comes from

`PreferencesFeature.MaxBanner` clips `MaxBannerColor` (`#484FFF`) under a
`y = maxY − A + (A / 2) · sin(−2πx / 20)` across the width, so its wavelength
is always 20 pt. The CSS mask repeats one 20 × 6 pt period of that curve. The
to within a few colour levels. The divider between releases reuses the wave
as a line.

Headings use the Marlin Soft SQ ExtraBold already bundled for onboarding (see
`Resources/Onboarding/README.md`). Paper `#FFFCEC`, ink `#100E22` and blue
highlight colours (`PreferencesSectionHighlight*`, `ARC_PreferencesFeature`
catalog). The mark is Parc's `Resources/AppIcons/Marks/Monochrome.png`.
`favicon.png` is `Marks/Borderless.png` centred in a 32 px square, since Chromium
stores favicons as square 16 and 32 px bitmaps:
`sips -Z 30 Borderless.png --out mark.png && sips -p 32 32 mark.png --out favicon.png`.
