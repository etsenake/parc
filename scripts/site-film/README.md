# Site film

The tools that make the videos on [parcbrowser.com](https://parcbrowser.com):
the silent film under the headline and the videos inside the field-guide
cards. Every frame of Parc in them is drawn offscreen from Parc's own interface
code: the real sidebar, themes, Peek, splits, command bar, Easel canvas, Notes
editor, Mini Player, capture tools, Library and window crank. Nothing launches
the app, opens a window or records the screen. The web pages inside the window
are the demo pages in `pages/`, because Chromium can't run here.

The renderers build only when `PARC_SITE_FILM=1` is set. Rendering is
manual. See the [website guide](../../docs/website.md) for how the videos sit on
the site.

## Layout

- `base/`: the starting render harness that every scene folder copied.
- Each scene's `Harness/` builds as a `parc-film-<folder>` SwiftPM executable,
  including `parc-film-base`. The package declares these targets only when
  `PARC_SITE_FILM=1` is set, so ordinary builds and test runs skip them. Each
  links the Parc, ParcCore and ParcEngineDoubles targets. The engine doubles live in
  [tests/ParcEngineDoubles](../../tests/ParcEngineDoubles)
  and supply the class names needed to load Parc without Chromium.
- `canon/Model.swift`: the shared Spaces, tabs and themes every scene uses. Each
  scene's `Harness/Model.swift` is a copy of it; keep them in sync.
- `film/`: the cutter. `Hero/main.swift` and `cuts.json` plan the film;
  `Plates/main.swift` and `plates.json` plan the card videos.
- `pages/`: the demo pages as HTML and the PNGs the scenes read. The PNGs come
  from a browser render of the HTML, outside these tools.

## Render a scene

From the repository root, build the scene you want in SwiftPM's default debug
configuration so the harness can access Parc's internal views. Link the
artwork next to the executable, where Parc normally looks for its resources.

```sh
(
set -e
export PARC_SITE_FILM=1
scene=spaces
timeout 900 swift build -j 4 --disable-keychain --product "parc-film-$scene"
bin=$(timeout 60 swift build -j 4 --disable-keychain --show-bin-path)
for resource in "$PWD"/Resources/*/; do
    resource=${resource%/}
    if [ "${resource##*/}" = SidebarPreview ]; then
        ditto "$resource" "$bin/SidebarPreview"
    elif [ ! -e "$bin/${resource##*/}" ]; then
        ln -s "$resource" "$bin/${resource##*/}"
    fi
done
cd "scripts/site-film/$scene"
timeout 900 "$bin/parc-film-$scene" out spaces ../pages/png/article.png ../pages/png/picnic.png ../pages/png/kite.png
)
```

Change `scene` and pass the corresponding arguments below. Keep the working
directory in the scene folder so relative paths resolve and the film cutter can
find the output. `parc-film-base` accepts the proof modes `still`, `video`,
`compare` and `all`.

| Folder | Arguments |
|---|---|
| `spaces` | `out spaces ../pages/png/article.png ../pages/png/picnic.png ../pages/png/kite.png` |
| `collapse` | `out collapse ../pages/png/article.png` |
| `crank` | `out crank ../pages/png/article.png` |
| `peek` | `out peek ../pages/png/article.png ../pages/png/kite.png` |
| `preview` | `out preview ../pages/png/article.png ../pages/png/kite.png` |
| `split` | `out split` (the film) and `out stacks` (the card) |
| `commandbar-easel` | `out commandbar ../pages/png` and `out easel ../pages/png` |
| `notes` | `out notes` (`notes-still` writes only the key frames and the strip) |
| `capture-archive` | `out capture` and `out archive` |
| `mini-card` | `out mini ../pages/png` and `out card 10 "Sam Rivera"` |
| `startpage` | `out startpage ../pages/png/kite.png` |

The full-window scenes write `out/<scene>.mov` (HEVC with alpha, 2880 × 1800,
60 fps, the window at 160, 36, 2560, 1680) plus a frame strip and a beats file.
Scene output and SwiftPM build products are ignored by Git.

## Cut the film and the card videos

From `film/`:

```sh
(
set -e
mkdir -p build
timeout 300 xcrun swiftc -O -parse-as-library Engine/*.swift Hero/main.swift -o build/hero
timeout 900 build/hero .
timeout 300 xcrun swiftc -O -parse-as-library Engine/*.swift Plates/main.swift -o build/plates
timeout 900 build/plates plates.json
)
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
