# What's New page

`scripts/build.py` renders `WhatsNew.html` with `scripts/whats_new.py` from the
repository's `release-notes.json` and bundles the result as
`Contents/Resources/WhatsNew.html`. Parc opens it at `parc://whats-new`; the
engine serves the bundled file there, as
[software updates](../../docs/software-update.md#whats-new-page-ownership)
explains. It's one self-contained file: the font, the
Parc mark, the grain texture and the favicon are inlined once each, and its
Content-Security-Policy allows no network loads and no script but its own
inline `WhatsNew.js`, by hash.
A missing `release-notes.json` renders the empty state.

When there are earlier releases, the timeline starts with a marker for the
current release. Each earlier row opens to its notes. See What's New opens `parc://whats-new/#from=…&to=…` with
the versions the update replaced and installed. When `to` is this page's
version, `WhatsNew.js` tags the earlier releases after `from` as new to you,
rings the previous version when its row is present and shows the
skipped-releases note when there are rows to open. A tab restored after a later
update keeps its old range and shows the plain page. Help ▸ Release Notes opens
the page without a range. Timeline labels come from `COPY` and `GROUPS` in
[whats_new.py](../../scripts/whats_new.py). Releases with no changes use the
no-notes line.

Preview it with the sample history:

```sh
python3 scripts/whats_new.py --notes tests/Packaging/fixtures/release-notes-sample.json build/whats-new/sample.html
```

## Where the design comes from

The banner uses blue `#484FFF`, layered grain and a repeating wave mask.
The wave follows `y = maxY − A + (A / 2) · sin(−2πx / 20)` with a 20 pt
wavelength. A 20 × 6 pt CSS mask holds one period; release dividers reuse the
wave as a line. An SVG noise filter uses `#2F39FF`, and the shared
`Resources/ThemeTextures/grain.png` tile repeats every 100 px with overlay
blending. Small inline assets keep the
page self-contained and quick to load.

Headings use Cormorant Garamond SemiBold Italic, selected from rendered
open-licensed typeface options. `CormorantGaramond-SemiBoldItalic.woff`
is a 21 KB Latin subset, at weight 600, of google/fonts'
`ofl/cormorantgaramond/CormorantGaramond-Italic[wght].ttf`. Only the page
carries the font; its [SIL Open Font License](../../Resources/WhatsNew/OFL.txt)
ships in the bundle. The subset can be recreated with:

```sh
python3 -m fontTools.varLib.instancer 'CormorantGaramond-Italic[wght].ttf' wght=600 --update-name-table -o semibold.ttf
python3 -m fontTools.subset semibold.ttf --unicodes='U+0020-007E,U+00A0-00FF,U+2013-2014,U+2018-201F,U+2022,U+2026' \
  --layout-features='kern,liga,calt,locl' --name-IDs='*' --flavor=woff --output-file=CormorantGaramond-SemiBoldItalic.woff
```

The page uses paper `#FFFCEC`, ink `#100E22` and blue `#3139FB`; the Heads up
callout has its own highlight colours in `WhatsNew.html`. `mark.png` is Parc's
`Resources/AppIcons/Marks/Monochrome.png` at twice the size the page shows it.
`favicon.png` is `Marks/Borderless.png` centred in a 32 px square, since Chromium
stores favicons as square 16 and 32 px bitmaps:
`sips -Z 30 Borderless.png --out mark.png && sips -p 32 32 mark.png --out favicon.png`.
