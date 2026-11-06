# Theme editor assets


- DotGrid and the four texture knobs came from `ARC_SpaceStyleEditor.bundle/Contents/Resources/Assets.car` (SHA-256 `55f8fa84237f73d4a58b5a6aaba0d96066bbb5e8ab6acffa919e9664aeab4029`). AppKit selected native 2× CGImage renditions, then ImageIO wrote PNG without resizing or redrawing. DotGrid is 799×801 pixels (original logical size 400×401); each knob is 112×112 pixels (nominal logical size 56 points; the source GrainKnob reports 56×57). Preserve native layout dimensions separately from pixel dimensions. DotGrid is template artwork.
- `sun.json`, `moon.json`, and `automatic.json` are unchanged Lottie files from the same bundle. Native selected appearance icons loop; the unselected icons are paused. The source renderer supports the used animation subset.

Extraction used semantic asset names; reused internal catalog rendition filenames are not identities. These exports preserve embedded image color profiles and alpha. Resource provenance does not establish complete editor visual/motion parity; see the project's parity ledger.

| File | SHA-256 |
|---|---|
| `DenimKnob.png` | `0ddd77aa473af3e78a3c51ed512e267b30ca1ceaf90d9247f0cdea38b1f870cb` |
| `DotGrid.png` | `d30f9a08cbc4999b4ea597b84113f0e411a15818cc6d0f41316bb34279b49e4b` |
| `GrainKnob.png` | `548894b96e434e6827b0615c5449d546002050357bffdc6a5145df87e7c4bf50` |
| `SandKnob.png` | `8d353869ad748044e3c3cca725a88e4c623093815fe1fa385fd6cde0c85de09b` |
| `TweedKnob.png` | `bd4942341e04d09b95d8bf309e14ec3a707f288e49e422ef2404a860d735cbf8` |
| `automatic.json` | `977a093912df30d3bb1f02b772a8786ee973af3c5d0f679ef95a631d4b843242` |
| `moon.json` | `9029532f85a02f90b21f58d9ed0268102cdaf462d6789fc99f54ee9023b7039c` |
| `presets.json` | `8b086432fb467a5319da91266cddb8f54fa5c249548d0c10a4bcd998d5abfaf7` |
| `sun.json` | `e6357eb2fd9a716a9f58f4797ca17be8642974d082b0f9076de70ee2d358839c` |
