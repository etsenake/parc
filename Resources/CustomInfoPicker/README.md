# Custom icon picker assets


## Fonts and emoji

- `ionicons.ttf` and `icomoon.ttf` come from
  `ionicons` (Fontello build of Ionicons) and `icomoon` (IcoMoon build of Feather).
  Every `SidebarIconType` except Linear and Figma uses an ionicons glyph;
  Parc's source selects the code points.
- The icomoon font supplies Remove (U+E9F0, trash) and eight emoji categories:
  smile (U+E9DE), sun (U+E9E3), coffee (U+E943), award (U+E919), truck (U+E9F6),
  gift (U+E971), heart (U+E97D) and flag (U+E96B).
- `emojis.json` is `db/emoji.json` from github/gemoji v4.1.0, unchanged: 1,870
  entries under the MIT license in `LICENSE-gemoji.txt`.

## Images and colors

`linear.png`, `linear@2x.png`, `linear-dark.png`, `linear-dark@2x.png`,
`figma.png` and `figma@2x.png` come from the `linear` and `figma` assets in
light or dark appearance and ImageIO exported 32 × 32 and 64 × 64 bitmaps without

The picker's named colors are recorded in source. `CustomizationBackground`
comes from `ARC_CustomInfoPicker.bundle`: Display P3 0.525/0.533/0.553 at
0.25 alpha in light appearance, and white at 0.25 alpha in dark appearance.
`BrandGray`, `ForegroundSecondary`, `ForegroundTertiary` and
`SidebarItemBackground` come from the BaseAssets catalog.

See [split groups](../../docs/split-groups.md) for picker behavior.
