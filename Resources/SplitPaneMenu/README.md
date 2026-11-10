# Split pane menu artwork


- Source catalog: `Contents/Resources/ARC_ContextMenus.bundle/Contents/Resources/Assets.car`, SHA-256 `5e9d36ac3261cf7c145a53f6e5cc532ebc2d0e46bb15a36e9260d875164063e8`.
- Each asset has a light (any appearance) and a Dark Aqua rendition, each at 1× and 2×, and no template mode. `name.png` / `name@2x.png` are the light renditions and `name-dark.png` / `name-dark@2x.png` the dark ones. AppKit loaded each asset by name from the bundle under the Aqua or Dark Aqua drawing appearance, and its CGImage was taken at the rendition's own pixel size (`NSImage.cgImage(forProposedRect:)`) and written by ImageIO without resizing, keeping its colour profile (sRGB or Generic Gray Gamma 2.2) and alpha. The vector renditions are not copied.
- Sizes: 18 × 18 points, except `icon-split-horizontal` and `icon-split-vertical` (Convert), 22 × 22.

| Item | Horizontal split | Vertical split |
|---|---|---|
| Move Left / Up | `icon-split-move-left` | `icon-split-move-top` |
| Move Right / Down | `icon-split-move-right` | `icon-split-move-bottom` |
| Add Left / Top | `icon-split-add-left` | `icon-split-add-top` |
| Add Right / Bottom | `icon-split-add-right` | `icon-split-add-bottom` |
| Separate Tab from Split | `icon-separate-from-split` | `icon-separate-from-split-menu-bottom` |
| Convert to Vertical / Horizontal Split View | `icon-split-vertical` | `icon-split-horizontal` |
| Share Split View… | `icon-split-share-horizontal` | `icon-split-share-vertical` |

`SplitPaneMenuArtwork` rebuilds each image from its two bitmaps per appearance and draws the light or dark one for the appearance it is drawn in. Copying the artwork does not by itself establish the menu's behaviour; see `docs/split-groups.md`.

| File | SHA-256 |
|---|---|
| `icon-separate-from-split-dark.png` | `1821bf8587eaff8e626039186090b986afbc2bd44c757efc68ab2acd9badd943` |
| `icon-separate-from-split-dark@2x.png` | `626014884c3c635e6d5c7979129a1f86c3d5bc262497026bc277fb883ca7c9fc` |
| `icon-separate-from-split-menu-bottom-dark.png` | `0ddef84da3d7b9fd0accb04aa4f90cc4263cbc20afcf18a53199cb0b5bce1a77` |
| `icon-separate-from-split-menu-bottom-dark@2x.png` | `affe1efd8107312fa4175c139d993a57d86b5d39bee20bcc58dd08aa8d203ec6` |
| `icon-separate-from-split-menu-bottom.png` | `fd1373af1ea94fdcfe8fe27b922a0454e1a389002d3898c38e000dd043592768` |
| `icon-separate-from-split-menu-bottom@2x.png` | `d74c166e2156e07979bf68f7f4e90a640147a1e6ebd83af73bd30d5c95bbaaa8` |
| `icon-separate-from-split.png` | `f6d49383a8510861050cdacbd248da94559df26d6c549e8314ce88ab9cf3bd9a` |
| `icon-separate-from-split@2x.png` | `e8713cb0d5764cffa878202ee6f0e6857143f16fdd25823d74798aa4c91d5466` |
| `icon-split-add-bottom-dark.png` | `2b7660e5a144b194476c49f82ffcd1acc84dd84f47f4a902090dca7d5d16f649` |
| `icon-split-add-bottom-dark@2x.png` | `6d8ffcf5f06ea1676f1c1b75737a1b826e4059c81651801d960e284b12cf6cfe` |
| `icon-split-add-bottom.png` | `a14b00e263478f9c3657d11536fa3014a94bc8e5b8a2125d6d311f6958c6e156` |
| `icon-split-add-bottom@2x.png` | `012a9412970e607932a539b4877ab25bc1aa3b9d4a64ad8fcc8a338169adbf53` |
| `icon-split-add-left-dark.png` | `ed55b2a6c2a561a9e3a9763b1ed900d0dfb7d9259ae41bec81b9d9cec10b75ec` |
| `icon-split-add-left-dark@2x.png` | `20a129153a96b9a12abc778555a7d6799abb7f824abd105032d89b7c285d9fcb` |
| `icon-split-add-left.png` | `876381884ccb94432edc7b542c65c1b32a0de2056177e6086f0edc4761639df3` |
| `icon-split-add-left@2x.png` | `f5282212f17206db24fa73f712916c85f06c980dd429251d992637647ded3339` |
| `icon-split-add-right-dark.png` | `8e57ff8c7bc48e165d80c5b46255aca145a3eeeade6855dad1977a23534e259f` |
| `icon-split-add-right-dark@2x.png` | `5cc9424c9513f210a74b01ac5ce98173ab4ee1a6a44e052365e3cf3e798b527f` |
| `icon-split-add-right.png` | `dc12cfb9fb35f54f81c81c191617232131d56cd8234e4ab71a7c808af6507cc6` |
| `icon-split-add-right@2x.png` | `1a6d5b3711c951cf9a5718b0520194a5b9e766ced0c9ad220f73094c1cd76664` |
| `icon-split-add-top-dark.png` | `5186c8463cbc6029d6894e7703a2ce31efae476bd796fc8745500b9d5f33c350` |
| `icon-split-add-top-dark@2x.png` | `548b8c24de907191bd6a194cfb884098993553c41c56d78cb493ab67d1e9e47d` |
| `icon-split-add-top.png` | `301f45b60ac441b9c468a7a167397b079b2aab53756640842a47bae1d694be58` |
| `icon-split-add-top@2x.png` | `68e6e8e3205066fec2933201af508037c188c2c84c724e9ef27e570f4564b7f9` |
| `icon-split-horizontal-dark.png` | `769a8a694ab979486c81fa24e4050106650965c9147e471609c182016addd951` |
| `icon-split-horizontal-dark@2x.png` | `2bea2ba677686b4533e00cbf227dff0c9462beafbf4c2a977a42698c88a4d1c4` |
| `icon-split-horizontal.png` | `261d024c740bccb08a926ec739edd3aa4a6640c340177ef793207aea8299310c` |
| `icon-split-horizontal@2x.png` | `eb22a62785c74c9dce749aff3d0da80e91367d2f70914e92363627eefdcb44e5` |
| `icon-split-move-bottom-dark.png` | `a6d2161f32a3e1a4ae475aa3d9f1d9da09122d495cdd310234936e454c96394d` |
| `icon-split-move-bottom-dark@2x.png` | `ea664077411211680870537a20c65b2c17048da680ced4b6199295294af9e8fc` |
| `icon-split-move-bottom.png` | `81e245b07c4f808b2778ce6db657dda746b2cb7b7a7aa3a65a0eebc4630d2c0d` |
| `icon-split-move-bottom@2x.png` | `659f60d6d3d2e744a4eac328843cc9a374ab134bbfe0d1a0abb2cd66f8a44939` |
| `icon-split-move-left-dark.png` | `a2c3228af596d689cf7a8ee3cc9f27e9a099f1d7bfb091082d337335dcd25b4d` |
| `icon-split-move-left-dark@2x.png` | `d12863704578b26e17ac67bf9825aa001e0cef232c0cc909dbe164dd5d5b8e01` |
| `icon-split-move-left.png` | `17ecb6b00361269759890c7eef76cb02a7f7ec2bdbbd46d19eca6fa0e4a5df96` |
| `icon-split-move-left@2x.png` | `3da5e01e0304d44526eb92d9a3b110791609f0f7f9827f0915c8a1dcbd2cf773` |
| `icon-split-move-right-dark.png` | `2175b919045b4ae3140fd011bb1ae526dbd560954f22279928af10c332a84f79` |
| `icon-split-move-right-dark@2x.png` | `6c2d27decfc8c938b3af2def767026f0d62c0fb9a7314b31cde309b70e410cf8` |
| `icon-split-move-right.png` | `be1e92df0e94c8c1a5c6427eae2209466735c35a4635093727978a4dc3ffdb80` |
| `icon-split-move-right@2x.png` | `a34b39e5f439c362d0a0b7382208ad71bbc1209999799b8839dab49b0a347311` |
| `icon-split-move-top-dark.png` | `7ae09328970f1a8eb8b534d5c66c5e70486005ce912db2a7d67c2a51b4f5f3b8` |
| `icon-split-move-top-dark@2x.png` | `8de27ca0826c4356055d9d26179f34db4d6dd0ceb9722acfebb9af6cf066382f` |
| `icon-split-move-top.png` | `852d6cdb7843a83eb1b959909c9f645c69ef97309fa8118178beb0d8c5d33487` |
| `icon-split-move-top@2x.png` | `3446aac1e015de36dc3db05fc6eee958adaf789c6130cd876777fbb0f83d2417` |
| `icon-split-share-horizontal-dark.png` | `b6d5d8900ca277c8132512c195dfef827975cfc4cc85bfba802813cd1b9f78d3` |
| `icon-split-share-horizontal-dark@2x.png` | `d12a767f25ac37f94b1622afb41834a159ef50648fa3c28333f45be1d84b1852` |
| `icon-split-share-horizontal.png` | `25a5b9464e7404e62f59460f6e67bd558a39ea5f2f9b155ba4a82c6b41d50b65` |
| `icon-split-share-horizontal@2x.png` | `9eaf920b6f65879d140b770b3cc3aaafb52cd6c0d0135e06bd96fb325773ed83` |
| `icon-split-share-vertical-dark.png` | `292cc0fe09946c17d3bde236560be09e327e4f7b53c2661092eca54da4924ff7` |
| `icon-split-share-vertical-dark@2x.png` | `5ef15c3a1abe9cffca16bd83ff08f1cf79de01519934c2baeac7a9cde4920964` |
| `icon-split-share-vertical.png` | `f0817fd823e4fd954e3555edc551616bea4ece82d5e7a22c64247dea8a3c1c54` |
| `icon-split-share-vertical@2x.png` | `99e0b4002c8fedd05ab3224baa8f4c48d119960152d050f062a033f8c1f16e50` |
| `icon-split-vertical-dark.png` | `32e2fbe908b9a815c942fa54bc788b6383f056d57811683a87c29d3c3a4bc73f` |
| `icon-split-vertical-dark@2x.png` | `a2eabdfaee18427e1db4507dcecd2b5540bb94b8db9d5e225be21c081d9641fd` |
| `icon-split-vertical.png` | `b03dc10a17b26c9090ea2452f945d5110827dfd3e2ebbef0a77cb9e5d2322557` |
| `icon-split-vertical@2x.png` | `5d3446176828fa7522e4071f7cff01339a9abaf27fe9835c719022f1d416de0c` |
