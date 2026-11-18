# Website

[parcbrowser.com](https://parcbrowser.com) is Parc's public home: one hand-built
page that introduces Parc and offers the download, plus the What's New page each
release refreshes. The source is an [Astro](https://astro.build) project in
[site/](../site/src/pages/index.astro), and GitHub Pages serves the static build
from this repository.

## What lives where

| Path | Contents |
|---|---|
| [site/src/pages](../site/src/pages/index.astro) | `index.astro` is the home page, `404.astro` the page GitHub Pages shows for an unknown address, and `whats-new/index.astro` the What's New page. |
| `site/src/components` | One component per home-page section, each with its own markup, scoped styles and script, plus the shared `Nav` and `Hills` and the What's New chrome in `whats-new/`. |
| `site/src/layouts/Base.astro` | The head every page shares: meta tags, fonts, favicon and the global stylesheet. |
| `site/src/styles` | `global.css` (tokens, type, buttons, shared animations and scenery) and `whats-new.css`, the What's New page's site chrome. |
| `site/src/scripts` | Browser code the sections share: the park sounds, the sky's time of day and small DOM helpers. |
| `site/src/data` | Structured content the sections render, such as the field guide's specimens. |
| `site/src/lib` | Build-time helpers: the download links, the release notes and the What's New renderer. |
| `site/src/content.config.ts` | The `releases` collection, read from `release-notes.json`. |
| `site/src/assets` | The fonts, the Parc marks (from `Resources/AppIcons/Marks`), the ten app icons (resized from [Resources/AppIcons](../Resources/AppIcons/README.md)), the 1200 × 630 link-preview image, the film and the field-guide clips. |
| `site/public/assets/fonts/OFL.txt` | The [SIL Open Font License](../site/public/assets/fonts/OFL.txt), shipped beside the built fonts. |

## How the page works

Astro builds the site into static HTML, CSS and JavaScript; nothing renders on
a server. Each section is a component with its own markup, a scoped `<style>`
and a TypeScript `<script>` that Astro bundles. Markup that never changes, like
the stars, the trail, the Spaces buttons and the icon picker, is rendered at
build time, and the scripts only add behaviour. `sky.ts` tracks the time of day
the sun sets and tells the hero, the trail and the membership card when it
changes; every chime goes through `sound.ts`.

Scoped styles use Astro's `where` strategy, which keeps every selector's
original specificity. Astro marks scoped elements with an `astro-…` class, so
scripts change classes with `classList` and never assign `className`.
`global.css` stays the layout's first import, which puts its rules ahead of
every component's, as they were in the old single stylesheet; a site check
fails if that order flips. HTML compression is off because it drops the
whitespace between inline elements.
Images go through `<Image>` as 1× and 2× PNGs, fonts through Astro's Fonts API,
and the film and clips are imported, so every shipped file has a content hash
in its name under `/assets/` and a browser never pairs a fresh page with a
stale file.

It makes no third-party requests. Every download button links to
`releases/latest/download/Parc-arm64.dmg` in
[parc-releases](https://github.com/etsenake/parc-releases): each release
publishes its disk image under that stable name (`ASSET` in
[package-dmg.py](../scripts/package-dmg.py)), so the link always fetches the
newest Parc without the page asking anyone. Fonts are self-hosted
so visitors aren't sent to Google, and the page carries no analytics or embeds;
its own rules card says nobody's counting visitors. A new external request,
tracker or hosted font would make that line untrue.

Each section hands over to the next with its own edge: the squiggle under the
hills, the Spaces window, the kite-string scribble, the swell into movie night,
the torn field-guide page, the stamp perforation above the membership card, the
menu bar and zigzag of the icons desktop, the clouds over the rules and the
sunset waves into the footer. Give a new section its own edge rather than
reusing one. The edges are pseudo-elements, not masks on a section: keep masks
and filters off `#guide`, because the field-guide overlay is fixed inside it and
would be clipped.

Each field-guide card opens a plate. Its entry in
`site/src/data/specimens.ts` gives the card and the plate their words and clip,
and `site/src/components/guide/Sketch.astro` holds its card drawing and scene
under the same id; the field guide renders each scene as a
`<template id="scene-N">` for the plate to copy. Add or remove both together.

Two parts of the home page come from the `releases` collection. The fresh paint
panel (`FreshPaint.astro`) shows the newest release's version, date, change
counts and three highlights with a link to What's New, and the download line
(`Download.astro`) names the version. With no notes, both are left out.
`site/src/lib/releases.ts` words them the way What's New does, and the site
checks compare the panel with `whats_new.py`.

`whats-new/index.html` is the same page the app bundles, rendered by
[scripts/whats_new.py](../scripts/whats_new.py) during the build. The Astro page
adds the site's head tags, nav and footer from `site/src/components/whats-new`,
the styles in `whats-new.css` and a lead line written for visitors. The page
keeps the app's content security policy, so the site chrome stays inline and
loads no files. The in-app page at `parc://whats-new` doesn't change and is
still bundled; the [What's New guide](../Sources/WhatsNew/README.md) and
[software updates](software-update.md#whats-new-page-ownership) own it.

## Build and preview

The site needs Node 22.23.4 or later (CI uses Node 26), and the build runs
`scripts/whats_new.py` with `python3`, the repository's Python 3.12 or later;
set `PYTHON` to use another interpreter.

```sh
cd site
npm ci                               # once, and after package-lock.json changes
npm run dev                          # live preview at http://localhost:4321
npm run check                        # type-checks the components and scripts
npm run build                        # writes build/site
npm run build -- --outDir /path/out  # or another folder
npm run preview                      # serves build/site
```

A build empties its output folder first, so point `--outDir` only at a folder
meant for the site. The npm scripts turn off Astro's telemetry, so run Astro
through them rather than with `npx astro`. Astro and its checker are pinned to
exact versions.

## Deploy and domain

[.github/workflows/site.yml](../.github/workflows/site.yml) publishes the site
with GitHub Pages. It runs on pushes to `main` that touch the site, its checks
or workflow, `release-notes.json` or the What's New sources, so every release
refreshes the What's New page and the fresh paint panel, and it can be run by
hand. It installs Node and the site's locked packages, type-checks them, runs
the site checks, builds into `_site`, uploads that folder and deploys it. The
job checks out only the files the build reads, so a new input needs adding to
both the workflow's paths and its sparse checkout.

The repository's **Settings → Pages** uses **GitHub Actions** as its source, the
custom domain `parcbrowser.com` and **Enforce HTTPS**.

DNS is at Hostinger:

| Type | Name | Value |
|---|---|---|
| A | `@` | `185.199.108.153` |
| A | `@` | `185.199.109.153` |
| A | `@` | `185.199.110.153` |
| A | `@` | `185.199.111.153` |
| CNAME | `www` | `etsenake.github.io` |

Hostinger's default parking record must stay deleted, or it competes with these.

## Product scenes

Every frame of Parc on the site is rendered from Parc's own interface code:
the real sidebar, themes, Peek, splits, command bar, Easel canvas, Mini Player,
capture tools, Library and window crank, drawn offscreen without launching the
app, with demo web pages standing in for Chromium's content. Nothing is a screen
recording or a mockup. The renderer and the film cutter live in
[scripts/site-film](../scripts/site-film/README.md); their outputs stay in the
ignored `build/` folder until a reviewed cut is installed into
`site/src/assets/media`.

- `media/hero.mp4` (H.264) and `media/hero-hevc.mp4` (HEVC) are the silent
  film under the headline, with `media/hero.jpg` as its poster. The frame is the
  Parc window edge to edge; the page adds its corners and shadow. It autoplays
  muted on a loop with no controls, plays only while on screen, and rises and
  scales into place as it scrolls into view. With Reduce Motion it shows the
  poster and plays on click.
- `media/plates/<clip>.mp4` and `.jpg` play inside a field-guide card's opened
  page in place of its drawing; the card keeps its drawing and its opening
  animation. A specimen's `clip` names its video, and a specimen without one
  shows its drawn scene ("sketched from life").

Every video is reviewed in the conversation before it ships. The film leaves
out the start page and its Easter eggs so people discover them in the app.
Movie night stays illustrated, because protected video can't be shown honestly.

## Copy and claims

Every product claim on the site must match the [product guide](product.md) and
the feature guide that owns it, such as [Split View](split-groups.md),
[Peek](peek.md), the [command bar](command-bar.md), [Easels](easels.md),
[Notes](notes.md), the [mini-player](media-mini-player.md),
[keyboard shortcuts](keyboard-navigation.md), [onboarding](onboarding.md) and
[browser import](browser-import.md).
When a feature changes, update its guide first and the site once a release
ships the change, following the `site-next` rule in AGENTS; link to the guides
rather than restating their details here. Site copy is short and
sweet: a changed line keeps the length and tone of the lines around it, and a
change never adds an essay, a new layout or a new design pattern. New cards,
sections and pages follow the approval rule, and every copy change gets the
dedicated copy review, both in
[AGENTS](../AGENTS.md#documentation-is-current-state-not-a-diary). The FAQ says Parc is
independent and not affiliated with The Browser Company; keep it. The font
licence ships as `assets/fonts/OFL.txt` beside the fonts, so the page carries no
credit line.

## Checks

```sh
python3 -m unittest discover -s tests/Site -v
```

The [site checks](../tests/Site/README.md) need `npm ci` in `site/`. They build
the site into a temporary folder and cover link and asset integrity, the
release parts of the home page, the What's New site copy (and an in-app page
free of it), outbound links limited to HTTPS on known hosts, pages that load
only `site.js`, a script that makes no network requests, field-guide cards with
a scene and an entry each, and the no-comments rule.
