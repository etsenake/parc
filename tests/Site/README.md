# Site checks

`test_site.py` checks the parcbrowser.com website in `site/` and the Astro
build made from it. It needs Node and the site's packages, but no network, and
never opens Parc, a browser or a window.

```sh
(cd site && npm ci)
python3 -m unittest discover -s tests/Site -v
```

The Pages workflow (`.github/workflows/site.yml`) runs this suite, after
`npm run check`, before every deploy, and a failure stops the deploy.

## Built site

One `npm run build` into a temporary folder feeds these checks, using the
Python that runs them for `whats_new.py`. A failed build stops them all and
shows its output.

- The home page, the 404 page and the What's New page are all built.
- The fresh paint panel announces the newest version from
  `release-notes.json`. Its date, change counts and highlights match the
  wording `whats_new.py` gives the same release, and the download line names
  the version.
- The home and 404 pages run only module scripts the build produced, and no
  built script names `fetch`, `XMLHttpRequest`, `WebSocket`, `EventSource` or
  `sendBeacon`.
- The What's New page carries the site nav, footer, visitor lead line and its
  one canonical URL, and keeps the app page's `default-src 'none'` policy.
  Every `src` on it, and every `<link>` `href` except the canonical one, is a
  `data:` URL, and its scripts are inline, so nothing it embeds needs the policy
  loosened.
- Every local `href`, `src`, `poster`, `srcset` entry and asset `data-`
  attribute in the three pages points at a built file inside the site, and
  none names a host without a scheme. Folder links need an `index.html`. Pages
  serves the 404 page at any depth, so its local links must start with `/`, and
  they resolve from the site root.
- Every `https://parcbrowser.com/...` URL, such as the social preview image,
  points at a built file.
- Every `url()` in the built stylesheets and inline styles is built.
- On the home and 404 pages, the global styles load before any scoped
  component rule.
- `OFL.txt` sits beside every built font.
- The icon picker offers one radio button per app icon.
- The guide cards' `data-open` buttons are numbered from 0 with no gaps, and
  each has its `scene-N` template.
- Every link or media attribute (`href`, `src`, `poster`, `content`, `action`)
  on the home and 404 pages that leaves the site uses https and points at
  github.com or parcbrowser.com. Release-note text that mentions an address is
  not a link.

## Sources

- The site's TypeScript and component scripts make no network requests.
- The components, pages, TypeScript, Astro config and CSS in `site/` carry no
  comments: no `<!--` in markup, no `/*` in CSS or JavaScript, and no
  JavaScript line starting with `//`. Inline `<style>` and `<script>` blocks
  and component frontmatter count too. The generated What's New page isn't
  checked here.
- The in-app What's New page from `whats_new.py` stays free of the site nav and
  footer.
