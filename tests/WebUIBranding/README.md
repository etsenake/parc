# WebUI branding checks

`WebUIBrandingTests` check the rules that put Parc's mark on Chromium's pages
([what users see](../../docs/app-icon-marks.md#parcs-mark-on-chromiums-pages)).
They compile the engine's own
[`webui_branding_rules.h`](../../Engine/ParcChromium/webui_branding_rules.h) into
the native test target, so they run the same edit code the browser runs.

```sh
swift test --filter WebUIBrandingTests
```

- The rule tests parse the mark's path, check its two outlines sit inside the
  24-unit box, about 20 units tall like the PNG, and run every rule on
  Chromium-shaped text: each applies in full, a missing, extra, unclosed or
  nested match leaves the text untouched, groups that don't depend on each other
  still apply, and overlapping matches apply nothing.
- The artwork tests require `Resources/AppIcons/Marks/Monochrome.svg` to carry
  exactly the path the engine compiles, and the dark logo, the colour-scheme
  logo (with its padded copy for the first-run animation) and the product icon
  the engine serves to be valid SVG drawing that path.

A rule that no longer matches a rebuilt Chromium page is skipped and logged at
runtime, never half applied. Checking each rule against the built pages needs a
Chromium build, so it belongs with the engine's own build checks.
