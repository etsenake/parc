# Website

[parcbrowser.com](https://parcbrowser.com) is Parc's public home: one hand-built
page that introduces Parc and offers the download, plus the What's New page each
release refreshes. The source lives in [site/](../site/index.html), and GitHub
Pages serves it from this repository.

## What lives where

| Path | Contents |
|---|---|
| [site/index.html](../site/index.html) | The whole page. The field-guide scene drawings sit at the end as `<template>` elements, one per plate. |
| `site/assets/site.css`, `site/assets/site.js` | The page's one stylesheet and one script. |
| `site/assets/fonts` | Self-hosted Instrument Sans, Instrument Serif, Caveat and JetBrains Mono, under the [SIL Open Font License](../site/assets/fonts/OFL.txt). |
| `site/assets/icons` | The ten app icons, resized from [Resources/AppIcons](../Resources/AppIcons/README.md). The Parc marks come from `Resources/AppIcons/Marks`. |
| `site/assets/og.png` | The 1200 × 630 image link previews show. |
| `site/404.html` | The page GitHub Pages shows for an unknown address. |
| [scripts/site.py](../scripts/site.py) | Builds the site. |

## How the page works

The page is plain HTML, CSS and JavaScript. There is no framework and no build
tool beyond `scripts/site.py`, so a change is an edit to the files in `site/`,
and what's there is what visitors get, apart from the slots the build fills.

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

Each field-guide card opens a plate. Its drawing is the matching
`<template id="scene-N">` in `index.html`; its words are the matching entry
in `site.js`. Add or remove all three together.

The build fills two slots from `release-notes.json`. The fresh paint panel
(`data-fill="latest-release"`) shows the newest release, its date and change
counts, three highlights and a link to What's New; with no notes it's left
out. The download line's `data-fill="version"` gains that release's version.
Keep both elements exactly as they are in `index.html`: the build replaces each
once and stops if either is missing or repeated.

`whats-new/index.html` is the same page the app bundles, rendered by
[scripts/whats_new.py](../scripts/whats_new.py), with a site header, a download
footer, a sharing description and a lead line written for visitors. The in-app
page at `parc://whats-new` doesn't change and is still bundled; the
[What's New guide](../Sources/WhatsNew/README.md) and
[software updates](software-update.md#whats-new-page-ownership) own it.

## Build and preview

```sh
python3 scripts/site.py build            # writes build/site
python3 scripts/site.py build /path/out  # or another folder
python3 -m http.server -d build/site
```

Then open <http://localhost:8000>. The build replaces an earlier site build in
the output folder, and refuses any other non-empty folder.

## Deploy and domain

[.github/workflows/site.yml](../.github/workflows/site.yml) publishes the site
with GitHub Pages. It runs on pushes to `main` that touch the site, its scripts,
checks or workflow, `release-notes.json` or the What's New sources, so every
release refreshes the What's New page and the fresh paint panel, and it can be
run by hand. It runs the site checks, builds into `_site`, uploads that folder
and deploys it. The job checks out only the files the build reads, so a new
input needs adding to both the workflow's paths and its sparse checkout.

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
ignored `build/` folder until a reviewed cut is installed into `site/media`.

- `media/hero.mp4` (H.264) and `media/hero-hevc.mp4` (HEVC) are the silent
  film under the headline, with `media/hero.jpg` as its poster. The frame is the
  Parc window edge to edge; the page adds its corners and shadow. It autoplays
  muted on a loop with no controls, plays only while on screen, and rises and
  scales into place as it scrolls into view. With Reduce Motion it shows the
  poster and plays on click.
- `media/plates/<clip>.mp4` and `.jpg` play inside a field-guide card's opened
  page in place of its drawing; the card keeps its drawing and its opening
  animation. A `SPECIMENS` entry's `clip` names its video, and an entry without
  one shows its drawn scene ("sketched from life").

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
When a feature changes, update its guide first and the site to match; link to
the guides rather than restating their details here. The FAQ says Parc is
independent and not affiliated with The Browser Company; keep it. The font
licence ships as `assets/fonts/OFL.txt` beside the fonts, so the page carries no
credit line.

## Checks

```sh
python3 -m unittest discover -s tests/Site -v
```

The [site checks](../tests/Site/README.md) build the site into a temporary
folder and cover link and asset integrity, slot filling, the What's New site
copy (and an in-app page free of it), outbound links limited to HTTPS on known
hosts, a script that makes no network requests, field-guide cards with a scene
and an entry each, and the no-comments rule.
