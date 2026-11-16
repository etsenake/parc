# Error pages

Parc's network error page and its security warning skin. The behaviour, and
which errors get Parc's own words, is described in
[web interactions](../../../docs/web-interactions.md#network-error-pages-and-security-warnings).

`generate_error_pages.py` (one folder up) builds them into one generated source,
`error_pages.cc`, for `//parc:browser`:

- `neterror.html`, `neterror.css` and `neterror.js` become the complete network
  error template that the child resource delegate returns for
  `IDR_NET_ERROR_HTML`. The drawings are inlined as `<template>` elements and
  the display font as a data URL.
- `interstitial.css` and `interstitial.js` become a `<style>` and a `<script>`
  that the browser resource delegate inserts into Chromium's own interstitial
  template, before `</head>` and `</body>`. The drawings become data URLs with
  each palette's colours filled in.
- `webapp.css` becomes a `<style>` the child resource delegate adds to
  Chromium's web-app offline page. Chromium's organization proxy page takes the
  interstitial style and script instead. `AddErrorPageSkin` in
  `error_pages.h` does every insertion.
- `art/` holds the drawings on a 120-point grid. Classes pick the colour: `k`
  ink, `a` accent, `kf`/`af` filled with the page colour, `p` a knockout ring,
  `kd`/`ad` dots. The plug's groups are what the offline toy moves.
- `display-font.woff.b64` is Cormorant Garamond SemiBold Italic, the What's New
  heading face, in base64 because the overlay carries only text. It is under
  the SIL Open Font License (`Resources/WhatsNew/OFL.txt`).

Chromium fills every `$i18n{...}` placeholder in these pages and crashes on an
unknown key, so the templates use only `textdirection` and `language`; the
generator refuses anything else. `tests/ErrorPages/check.py` builds the same
pieces and loads them; edit, then run it.
