# Welcome resources


SHA256: `32646cdf73797e8b84252fbeaf334ae1f4ac09eae8ad6f97f25e74a8b9aa7e0a`.
reported duration 21.336 seconds. `scripts/build.py` copies the complete Resources
tree, and already links AVFoundation. The P-based welcome artwork comes from
Parc's existing `AppIcons/Original.png`.

Playback/ownership and the remaining reference gaps are described in
`docs/onboarding.md`.

## Typeface and background

`orb.mp4`, `background.mp4`, four `grain-*` frames and `animatingOrbBlob1` mask.
are exact file copies. The PNG grain/mask files are native catalog image exports;
the mask is a 630×630 raster of the preserved vector asset. Posters are native
AVFoundation extractions of each video's first frame, not additional reference
artwork. The four grain images are 2100×1500. The 100×100 videos are silent,
lasting 6 seconds (orb) and 8 seconds (background).

Every resource is loaded from Parc's bundle. The packager already copies this
tree, and the app already links AVFoundation; CoreText is imported by the Swift

| Resource | SHA256 |
| --- | --- |
| `MarlinSoftSQ-ExtraBold.otf` | `55ce90d95b1a57b66700107717703ff071fee344e2b169eb7751ed9cd0053e6f` |
| `background-poster.png` | `673fb7322b6720376498d219ae0d181fb54229ea248d65c48166a5f3451a110d` |
| `background.mp4` | `a41ea53b7a18898292cf139e971b1bebe83634e40fe238b5a70b105b5965693e` |
| `grain-1.png` | `32abd8646f2cd59e5e5055ee158aa0cbfcbf7d53344c2ffc99f7c61c55d7661f` |
| `grain-2.png` | `bb897382ab13de73d53ef08301876b92e71be702a4e59b4d4a73401f35f9096f` |
| `grain-3.png` | `5b1a58cbffe35ac508fe7934c737b2627d55b0472b15904ccb46a0abb2e28a0b` |
| `grain-4.png` | `e67765a76d703c706e9999abb031ea29dd2b40e8dac3796c55fd5d4a2592b898` |
| `orb-mask.png` | `58bf0b22063e7c93005a34d216fe9d06156ba37ece70ce7a4d245be71df03e12` |
| `orb-poster.png` | `e984972595eba0deb5a56a9c397b6041a9000fd52a064dbdca4235f2ba0b1600` |
| `orb.mp4` | `886a134f48ce21d0916b99998e5f10bdb58730965a348aff9989b24187fb03bf` |

## Favorites artwork

The nine setup apps use the recovered BaseAssets resource keys (`twitter`,
`gmail`, `gcal`, `spotify`, `youtube`, `notion`, `slack`, `figma`, `outlook`).
with explicit Aqua and Dark Aqua drawing appearances. Twitter has separate
light/dark artwork (the current catalog uses X); all others share one rendition.
Original logical image sizes are retained at 2x resolution. These are bundled

| Resource | SHA256 |
| --- | --- |
| `favorite-figma.png` | `bb9a0869fe23451902e57850a168145bd2a4f23c7ac32889ed9a018aee0f0cfe` |
| `favorite-gcal.png` | `f5acd8da5d9fae0fdb33869c5da22d938c738a5a1469ab9d88754bb7093aa3d0` |
| `favorite-gmail.png` | `91f0ccfa0e807a396f755843899e7eff678e33cffddd3aa05f4aa9ed5989799b` |
| `favorite-notion.png` | `0c8ac6404ac54030c8f1e85dc87ba3598a1dc39ea8a5264dd92fc1c75f8f690f` |
| `favorite-outlook.png` | `21f253f3313e5c0e24baa22321c92a06cfb883763431f48ad08eb7530335fe10` |
| `favorite-slack.png` | `dbef0e78f1f045e95622c6cd9b3862ab04989e2bf518a33577175a7c031149ee` |
| `favorite-spotify.png` | `a4547c6f76fec8a603ccfd76999634a56243d49315942241053ff706b1781319` |
| `favorite-twitter-dark.png` | `bce519051ec3c5d254bb014c3bec151d05bc6e68cf8a2d322600f6289c53a09f` |
| `favorite-twitter.png` | `2c6eb630fa2f9d33fd0ea0ec789d7045980c9608db4a24ed34385592b533be2a` |
| `favorite-youtube.png` | `a2e80605f61f643ec336958bbfb9d5ff463aa94e1d78b5b70c2b41e9e845ec00` |
