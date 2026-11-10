# Split pane menu artwork

`ARC_ContextMenus.bundle/Contents/Resources/Assets.car`. Parc loads standalone

Each asset has light and Dark Aqua renditions at 1× and 2×:
`name.png`, `name@2x.png`, `name-dark.png` and `name-dark@2x.png`. AppKit selected
the named image under the matching drawing appearance; ImageIO exported its
native bitmap without resizing, preserving sRGB or Generic Gray Gamma 2.2
color and alpha. Vector renditions are not included, and these images are not
templates.

| Item | Horizontal split | Vertical split |
|---|---|---|
| Move Left / Up | `icon-split-move-left` | `icon-split-move-top` |
| Move Right / Down | `icon-split-move-right` | `icon-split-move-bottom` |
| Add Left / Top | `icon-split-add-left` | `icon-split-add-top` |
| Add Right / Bottom | `icon-split-add-right` | `icon-split-add-bottom` |
| Separate Tab from Split | `icon-separate-from-split` | `icon-separate-from-split-menu-bottom` |
| Convert to Vertical / Horizontal Split View | `icon-split-vertical` | `icon-split-horizontal` |
| Share Split View… | `icon-split-share-horizontal` | `icon-split-share-vertical` |

Images are 18 × 18 points except the two Convert images, which are 22 × 22.
`SplitPaneMenuArtwork` combines the two bitmap scales for each appearance and
selects the image for the menu's current appearance. See
[split groups](../../docs/split-groups.md) for menu behavior.
