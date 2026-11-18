# Site film

The tools that make the videos on [parcbrowser.com](https://parcbrowser.com):
the silent film under the headline and the videos inside the field-guide
cards. Every frame of Parc in them is drawn offscreen from Parc's own interface
code: the real sidebar, themes, Peek, splits, command bar, Easel canvas, Mini
Player, capture tools, Library and window crank. Nothing launches the app,
opens a window or records the screen. The web pages inside the window are the
demo pages in `pages/`, because Chromium can't run here.

These tools never run as part of the checks. See the [website guide](../../docs/website.md)
for how the videos sit on the site.

## Layout

- `base/`: the starting render harness that every scene folder copied.
- One folder per scene: `spaces`, `collapse`, `crank`, `peek`, `preview`,
  `split`, `commandbar-easel`, `capture-archive`, `mini-card`, `startpage`.
  Each has a `build.py` that compiles Parc's sources plus its `Harness/` into a
  `render` binary, and generates patched copies of a few sources into `gen/`.
- `canon/Model.swift`: the shared Spaces, tabs and themes every scene uses. Each
  scene's `Harness/Model.swift` is a copy of it; keep them in sync.
- `film/`: the cutter. `Hero/main.swift` and `cuts.json` plan the film;
  `Plates/main.swift` and `plates.json` plan the card videos.
- `pages/`: the demo pages as HTML and the PNGs the scenes read. The PNGs come
  from a browser render of the HTML, outside these tools.

Builds and renders write into each folder's `gen/`, `out/` and `build/`, which
git ignores. Parc loads some artwork from resource folders beside the binary:
link them into a scene folder with
`for d in ../../../Resources/*/; do ln -sfn "$d" .; done` before rendering, and
give `preview` a real copy of `Resources/SidebarPreview`.

## Render a scene

From the scene's folder, build once, then render:

| Folder | Render |
|---|---|
| `spaces` | `./render out spaces ../pages/png/article.png ../pages/png/picnic.png ../pages/png/kite.png` |
| `collapse` | `./render out collapse ../pages/png/article.png` |
| `crank` | `./render out crank ../pages/png/article.png` |
| `peek` | `./render out peek ../pages/png/article.png ../pages/png/kite.png` |
| `preview` | `./render out preview ../pages/png/article.png ../pages/png/kite.png` |
| `split` | `./render out split` (the film) and `./render out stacks` (the card) |
| `commandbar-easel` | `./render out commandbar ../pages/png` and `./render out easel ../pages/png` |
| `capture-archive` | `./render out capture` and `./render out archive` |
| `mini-card` | `./render out mini ../pages/png` and `./render out card 10 "Sam Rivera"` |
| `startpage` | `./render out startpage ../pages/png/kite.png` |

`python3 build.py` builds in about a minute. Each scene writes
`out/<scene>.mov` (HEVC with alpha, 2880 × 1800, 60 fps, the window at
160, 36, 2560, 1680) plus a frame strip and a beats file.

## Cut the film and the card videos

From `film/`:

```sh
xcrun swiftc -O -parse-as-library Engine/*.swift Hero/main.swift -o build/hero && build/hero .
xcrun swiftc -O -parse-as-library Engine/*.swift Plates/main.swift -o build/plates && build/plates plates.json
```

The film reads `../<scene>/out/<scene>.mov` and writes `out/hero-web.mp4`,
`out/hero-web-hevc.mp4` and `out/hero-poster.jpg` at 1920 × 1260. The cards
write `out/plates/<name>.mp4` and `.jpg`. Change the order, trims and camera in
`Hero/main.swift` and `cuts.json`, or a card's crop in `plates.json`.

After the result has been reviewed, copy `hero-web.mp4` to
`site/src/assets/media/hero.mp4`, `hero-web-hevc.mp4` to
`site/src/assets/media/hero-hevc.mp4`, `hero-poster.jpg` to
`site/src/assets/media/hero.jpg` and the plates into
`site/src/assets/media/plates/`, then publish the site as usual.

## Rules

- Frames show the Parc window edge to edge, with no backdrop; the page adds the
  corners and shadow.
- No audio, no real brand names, and only motion Parc's code really has.
- Every Work, Home and Side Quest scene starts from `canon/Model.swift`.
