# Site checks

`test_site.py` checks the parcbrowser.com website in `site/` and the build that
`scripts/site.py` makes from it. It needs no network and never opens Parc, a
browser or a window.

```sh
python3 -m unittest discover -s tests/Site -v
```

The Pages workflow (`.github/workflows/site.yml`) runs this suite before every
deploy, and a failure stops the deploy.

## Built site

One `site.py build` into a temporary folder feeds these checks. A failed build
stops them all and shows its output.

- The home page, the 404 page and the What's New page are all built.
- The latest-release slot is filled and announces the newest version from
  `release-notes.json`, and the download line names it.
- The What's New page carries the site nav, footer and its one canonical URL
  and keeps the app page's `default-src 'none'` policy. Every `src` on it, and
  every `<link>` `href` except the canonical one, is a `data:` URL, so nothing
  it embeds needs the policy loosened.
- Every local `href`, `src` and `poster` in the three pages points at a built
  file inside the site, and none names a host without a scheme. Folder links
  need an `index.html`. Pages serves the 404 page at any depth, so its local
  links must start with `/`, and they resolve from the site root.
- Every `https://parcbrowser.com/...` URL, such as the social preview image,
  points at a built file.
- Every `url()` in `site.css` and every icon in the picker's `ICONS` list is
  built.
- Every link or media attribute (`href`, `src`, `poster`, `content`, `action`)
  on the home and 404 pages that leaves the site uses https and points at
  github.com or parcbrowser.com. Release-note text that mentions an address is
  not a link.

## Sources

- The guide cards' `data-open` buttons are numbered from 0 with no gaps, and
  each has its `scene-N` template and a `SPECIMENS` entry in `site.js`.
- Every `SPECIMENS` entry with a `clip` has its `media/plates/<clip>.mp4` video
  and `.jpg` poster.
- `site.js` makes no network requests: it never names `fetch`,
  `XMLHttpRequest`, `WebSocket`, `EventSource` or `sendBeacon`.
- The HTML, CSS and JavaScript in `site/` carry no comments: no `<!--` in
  pages, no `/*` in CSS or JavaScript, and no JavaScript line starting with
  `//`. Inline `<style>` and `<script>` blocks count too. The generated What's
  New page isn't checked here.
- `OFL.txt` ships with the fonts and every `@font-face` `url()` exists.
- The in-app What's New page from `whats_new.py` stays free of the site nav and
  footer.
