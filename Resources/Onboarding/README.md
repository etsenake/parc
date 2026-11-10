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

The nine setup apps use the original BaseAssets resource keys (`twitter`,
`gmail`, `gcal`, `spotify`, `youtube`, `notion`, `slack`, `figma`, `outlook`).
with explicit Aqua and Dark Aqua drawing appearances. Twitter has separate
light/dark artwork (the current catalog uses X); all others share one rendition.
Setup draws each at 40 points. Twitter (both), Gmail, Google Calendar, Slack,
Figma and Outlook are 120×120 drawings of the catalog's vector (SVG)
others), in Display P3 because the Slack, Gmail and Google Calendar vectors
specify Display P3 colours. They are pixel-exact at 3x and sharp at 2x; the
catalog's 48 and 64 px bitmaps would be enlarged. Spotify, YouTube and Notion
are 240×240 (Notion's catalog source is a 120 px PNG with no vector). These
bundle.

| Resource | SHA256 |
| --- | --- |
| `favorite-figma.png` | `23bc39ba1ff2206f21b52d095cbd81a81d5baebcc9d222d2cb16c7584f3e5b47` |
| `favorite-gcal.png` | `7cf29758961a0b0bb2eebd7ab3e242b66d87c6f10b056554e7cea2b161650a85` |
| `favorite-gmail.png` | `c19a856478ede52d43864642a12a8a800d8f5bb5a39005095c7304b8ca19ae7b` |
| `favorite-notion.png` | `0c8ac6404ac54030c8f1e85dc87ba3598a1dc39ea8a5264dd92fc1c75f8f690f` |
| `favorite-outlook.png` | `77279b0b4803d74ba50eab0f5d371ff728a3e72343517b1f7f7f04634429d4c9` |
| `favorite-slack.png` | `7d11d197966dd197b50620cc62c0947347d1c0b265e08b260ed3b85c3108f1f4` |
| `favorite-spotify.png` | `a4547c6f76fec8a603ccfd76999634a56243d49315942241053ff706b1781319` |
| `favorite-twitter-dark.png` | `1dcbe9988512ec6d0dca9fe8a8c9d4d022746a91dcfe9a5d948d873ca541e752` |
| `favorite-twitter.png` | `a2a1a872429b52dc99d0a6db2ab188870a5f914649129ee113f1189e7f5c196a` |
| `favorite-youtube.png` | `a2e80605f61f643ec336958bbfb9d5ff463aa94e1d78b5b70c2b41e9e845ec00` |
