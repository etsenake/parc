# Library artwork



The Library entry and EmptyFavicon assets above are template images (the catalog's `Template Mode: template`). Each is kept as the catalog holds it:

- The vector rendition (`.pdf`, `.svg`) is the catalog's stored payload: the CoreUI rendition's raw-data block, byte for byte (the SVG is the lzfse-decompressed payload).
- The 1× and 2× bitmaps (`.png`, `@2x.png`) are the catalog's compiled renditions as AppKit returns them for the named image; ImageIO wrote those CGImages without resizing or redrawing, keeping their colour profiles (Generic Gray Gamma 2.2 for the icon layers, sRGB for EmptyFavicon) and alpha.


| File | SHA-256 |
|---|---|
| `EmptyFavicon.png` | `68ce600e150b7abc0b92849b2adbc0c75ee9da9f90940f1683551d24d58e9588` |
| `EmptyFavicon.svg` | `4f298519f16c3add785a401b515ed071eb10de902d1ae7c609df65a3f6ff9052` |
| `EmptyFavicon@2x.png` | `7c60b23c4a66b4fa29252b86e95b9eb7e25093a8715507a46b77c73b173c2eb0` |
| `box.pdf` | `52774965c5b67f7cc3369d397ff37f1a1ee1418ba2b3110660e113eb23c5da05` |
| `box.png` | `d18edab2ba459dd1e6db1e14e35e6148ac70cf92343d5e389aaba1c9df4b152d` |
| `box@2x.png` | `b1a281b8fe6870724af4ba04aa96b2f2506813723c0eada03ef0e5224df3bed2` |
| `circle.pdf` | `455bf930089c413cef0fc466e72b7e141ccf959b2fa4729ed6815a88eaa9cd6c` |
| `circle.png` | `974211a1e3db991bb97968ae4528d46a84dbee0ec6402da7f8549202476b1fa5` |
| `circle@2x.png` | `80124245b37b4352040024e518ad0cded1c88bb5b189a08a6dec120d697914a4` |
| `glow.pdf` | `0ed84fb85507cac231aaeb2cf120360d0c36c9430e5ae37e6b957d20a1be7df6` |
| `glow.png` | `1e008a605e461be8b7875f45cb4c1dc0d0253090d03a150341d7ff3c1530c561` |
| `glow@2x.png` | `82c129676ad89fdd702b06defab8db701fb468baf2f961b2aad1e99b8f4f5caf` |
| `star.pdf` | `ea981f2b67b10380ac93121d949f80bc163956c386e0481b6a85b97fc7509cd2` |
| `star.png` | `32a09bd7840f5d1665f0a5125e00a33d65fd588f1c3a26733653a264637c009f` |
| `star@2x.png` | `a74e346454d2427192af3f08c3f9214baa5fac4516c849c5d95a88602cbdf8aa` |
| `triangle.pdf` | `c18298bd467e0c5b717839919df1291cdbd5816d557140327d857b044f854b21` |
| `triangle.png` | `f0980d7b496243dff9b1852e1f0bbb66f7a60df27a5edf3e01590486d720de2c` |
| `triangle@2x.png` | `bffe42132a30285197737f19bc2b2cfe5ad87ec4f7bb6daceeac8aecf1b0f32b` |

The Easels & Notes title-card images (`easel`, `note`, and their `-dark`
variants) are the 18 × 18 and 36 × 36 compiled representations from the
(SHA-256 `eeaeb5ce411296585d189fc8352afacb8a487079a1c299cf3a300d3ae4a1145f`).
They correspond to the catalog's `icon-home-easel.svg`,
`icon-home-easel-dark.svg`, `icon-home-notes.svg`, and
`icon-home-notes-dark.svg`. AppKit's image representations were written as PNG
through ImageIO without resampling; Aqua and DarkAqua selection was checked
against AppKit's appearance-resolved image. These are colored artwork, not
template images. The retained PNG hashes are:

| File | SHA-256 |
|---|---|
| `easel.png` | `7490e13a274c542d0a410d4fe547eab127e23191efda00db77cf07d2f0aec3ea` |
| `easel@2x.png` | `6137b3eb50b74e3a6ccdaafe46f833b1388b39458d74fac9dac29fa7a6974be9` |
| `easel-dark.png` | `bc4cb271891f7da5d1cb497c0687faf994c1d4aa09d47034a6a2ff31abb41465` |
| `easel-dark@2x.png` | `e33befe18254b15d91236f9fc79df679e6047322989b0a45c249956cf442cd63` |
| `note.png` | `98c481a4a35f73cb0a15ea03509b22d68241291545dd1e645998ec9a0834ca98` |
| `note@2x.png` | `2a5d566bcd9b4aaae07189fef5e47a96fe0912b64b8c60aea89f216de2bc3ba7` |
| `note-dark.png` | `41c2d39a884a3b22d1d90e8aeb38a5d0a39906f9e43036e5777bd6615b41bab7` |
| `note-dark@2x.png` | `2196e827ed951abf33d06803efc2b23e1c863f40141233dc0633480064868d76` |

The Library rail icons (`screenshots`, `downloads`, `easels`, `spaces` and
`archive`.json) are the Lottie compositions shipped beside that same
copied byte for byte; `boosts.json` is not copied because Boosts are excluded.
Parc colors each composition's `primaryColor` and `secondaryColor` layers
with the theme's `maxContrastColor` and `cutoutColor`. Selection plays
`hover-start` to `selection-end` once unless Reduce Motion is on. Deselection
does not stop a running play. Completion parks on `selection-end`; an unplayed
page shows the start frame (`ip`, frame 0).
`LibraryRailAnimation` draws these files directly; no Lottie runtime is copied.

`easels`, `spaces` and `archive` carry 12 Offset Path items (`op`, amount −0.5,
`Contents/Frameworks/Lottie.framework/Versions/Current/Lottie` (SHA-256
`0ba1dc6651801f090d0cf5b031a4b0ea2b5b124d4015c80ee11a59584ef415bc`), the arm64
slice's `__swift5_reflstr` section lists the shape item's fields (`isEnabled`,
`name`, `type`, `hidden`) followed by its shape-type cases: `ellipse`, `fill`,
`gradientFill`, `group`, `gradientStroke`, `merge`, `rectangle`, `repeater`,
`round`, `shape`, `star`, `stroke`, `trim`, `transform`, `unknown`, then
`RawValue`. None of the section's 1,300 names is an offset path, and the
apply them, Parc's affected shapes draw about 0.1 point fuller per edge at 28
points.

| File | SHA-256 |
|---|---|
| `archive.json` | `b26687a38114a3f72f2de7ab3c8c2febdc59c7c84e9b87a6069f374890942acc` |
| `downloads.json` | `2d01cdaa855829318661bb0ca94136015e033aa6de6f62f1fa8ce92c360bc017` |
| `easels.json` | `30c1299da7f108c97912574d6373c492dd1226e15b72eca8b7edfbe2337875d5` |
| `screenshots.json` | `2ddf7063fe4e6de2d83d68123beb8f459c5424539bd3fb37e25b650622df2e8c` |
| `spaces.json` | `f87b671825d99100c476827809936aea5ce8bfa9730c5809a1411247aefb0fbd` |
