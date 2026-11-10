# Site Control Center artwork


- `icon-control-center` is the toolbar and address-pill entry glyph.

Every asset is a template image (the catalog's `Template Mode: template`), loaded by its semantic asset name from the bundle:

- The 1× and 2× bitmaps (`.png`, `@2x.png`) are the catalog's compiled renditions as AppKit returns them for the named image; ImageIO wrote those CGImages without resizing or redrawing, keeping their Generic Gray Gamma 2.2 profile and alpha.
- The `.pdf` is the catalog's SVG rendition (its `_NSSVGImageRep`) drawn once into a single-page PDF context at the 1× size, so its vector paths are kept; the SVG payload itself is not stored.


| File | SHA-256 |
|---|---|
| `capture-full-page.pdf` | `75a285ec737a50d03bdb27fa738c97d0f6a8bb1f3137d475cd1c24f5952d4bb6` |
| `capture-full-page.png` | `e137384477f1c4b1c9ac2734c54e7f8a820626e34a31facde976c27b025d922c` |
| `capture-full-page@2x.png` | `5f694bf20d1e5761974f5b5d6343aaa623cfbc573bd87b1f5d91ac2862c2e1b1` |
| `copy-url.pdf` | `8ff8833f9104da021a159cb566c6a4abac3e7f32ab044502eae2f061b164d93d` |
| `copy-url.png` | `dff0780d2704da2326b716234013ec8aaa4c097e90ef48d4d25c9a263ddbf002` |
| `copy-url@2x.png` | `e2cc5885b2a17de67d48c49eefe482d94dd02403a76f34b541f5322e9e682676` |
| `icon-control-center.pdf` | `85d2ac8c2276b8e60eae5caf681a34e7afbe717f67fa573c844725539c4c169c` |
| `icon-control-center.png` | `c48666bf7ec550ba1e8e413f946b960ed105e6d46863dd16705171af7d54f192` |
| `icon-control-center@2x.png` | `94272f4f6ecedf55ab5b133438d344eaf0964d13d9605efa023de1d232aa6ed5` |
