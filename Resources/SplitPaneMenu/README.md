# Split pane menu artwork

Parc's split-menu images: a soft frame of the pane layout with one strong accent,
an arrow or plus breaking through the frame, or a blue arrow for separating a
tab. Frames are 20% black (20% white in Dark Aqua) and accents are solid ink,
with blue #418AF9 (#7AABFA dark) for Separate. Both use 1.5-point strokes snapped
to the 2× pixel grid: frame lines are centred on pixel centres so their three
pixels have hard edges, and accents are centred on pixel boundaries.

Each asset has light and Dark Aqua renditions at 1× and 2×: `name.png`,
`name@2x.png`, `name-dark.png` and `name-dark@2x.png`, rendered from vector
geometry with 8× supersampling. These images are not templates.

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
