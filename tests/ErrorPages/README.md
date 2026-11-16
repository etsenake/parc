# Error page checks

`check.py` builds Parc's network error page and security warning skin with the
engine's own generator, fills them the way Chromium does and loads every
variant in a windowless WebKit view, light and dark. It never opens a window or
another app.

```sh
python3 tests/ErrorPages/check.py
python3 tests/ErrorPages/check.py --sheet-dir build/tests/error-pages/sheet
```

- `fixtures.py` holds Chromium-shaped page data for each network error and
  warning variant, from the strings Chromium 157 produces.
- `pages.py` mirrors Chromium's page building: `$i18n` replacement (failing on
  a missing key, as Chromium crashes), the appended `loadTimeDataRaw`, and for
  warnings the browser delegate's skin insertion plus the text-defaults style.
- `chromium/` is Chromium 157's interstitial template, scripts and styles,
  copied with their licence headers, so warnings run Chromium's real page logic
  under Parc's skin. Refresh it at a Chromium upgrade. `load_time_data.js` is a
  small stand-in for Chromium's `loadTimeData` module.
- `Runner.swift` injects recording page controllers before the page's scripts,
  runs each scripted step and reports errors, policy violations, controller
  calls, the title and the visible text.

Each page must load without script errors or Trusted Types violations and must
not show `chrome://`. The scripted checks cover Reload and Go back, Details,
links that open Details, DNS-check updates, the offline toy and its high score,
the back-online line, subframe errors, the fallback to Chromium's words, and
Go back appearing only when the renderer says there is history behind the
page. For warnings they cover Parc's words on every type, the steady Details
label, the primary and proceed commands, the proceed click delay, the typed
bypass, reporting and certificate details. The generated C++ is also
syntax-checked with the system compiler.
