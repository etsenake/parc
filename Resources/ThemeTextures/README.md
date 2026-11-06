# Theme renderer textures


The original image loader obtains `NSImage` by semantic resource name, then its `CGImage` compatibility getter calls `CGImageForProposedRect:context:hints:` with the image's logical-size rectangle and nil context/hints. Repeating that read-only conversion selects grain 200×200 pixels and sand/denim/tweed 100×100 pixels. ImageIO exported those CGImages directly without resizing or redrawing, preserving sRGB profiles and alpha. The exported files were compared byte-for-byte with a fresh nil-context conversion.


| File | SHA-256 |
|---|---|
| `denim.png` | `971da25f447cf5768376842db1be3e673c34f557ebfa03ae5776b1c440e80de2` |
| `grain.png` | `8fbdb4aafc4995ccad07c908f6b10100dd06c7033dc7b6de0f857c7a788eb5fc` |
| `sand.png` | `97304d64f6c096c2be7e8d50a636470676e9da7a4bbf745cecddb06bf16074af` |
| `tweed.png` | `b347fae47b4664129bf0938822c110223a18f5890ce8e98a91a0881a2149af26` |
