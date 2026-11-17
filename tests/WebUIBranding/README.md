# WebUI branding checks

`check.py` checks the rules that put Parc's mark on Chromium's pages
([what users see](../../docs/app-icon-marks.md#parcs-mark-on-chromiums-pages))
and, with an engine workspace, every piece of Chromium they rely on. It compiles
`Tests.cc` with the system compiler against the engine's own
[`webui_branding_rules.h`](../../Engine/ParcChromium/webui_branding_rules.h), so
the check runs the same edit code the browser runs. It opens no window or app.

```sh
python3 tests/WebUIBranding/check.py
python3 tests/WebUIBranding/check.py --chromium "$PARC_ENGINE/chromium/src" --require-engine
```

- The unit tests parse the mark's path, check its two outlines sit inside the
  24-unit box, about 20 units tall like the PNG, and run every rule on Chromium-shaped
  text: each applies in full, a missing, extra, unclosed or nested match leaves
  the text untouched, groups that don't depend on each other still apply, and
  overlapping matches apply nothing.
- The artwork check requires `Resources/AppIcons/Marks/Monochrome.svg` to
  carry exactly the path the engine compiles, and the dark logo, the
  colour-scheme logo (with its padded copy for the first-run animation) and
  the product icon the engine serves to be valid SVG drawing that path.
- The engine check finds each branded resource's built file through the
  engine's generated resource lists and applies its rules there with exact
  counts. A built file older than its Chromium sources is skipped with a note,
  or fails with `--require-engine`, since only a fresh build shows the text the
  browser will load. It also requires each rule's
  text in Chromium's sources, and checks the pages that rely on the replaced
  resources: the toolbar and drawer still load the dark logo, Settings, Safety
  Hub and the certificate manager still name the product icon, the certificate
  manager still loads the shared icon set, the version page still uses the
  replaced logos, and the version and What's New favicons, the first-run and
  profile picker logos and the current channel logo still use the resource IDs
  Parc draws. A built bundle that both carries its own copy of the product icon
  and uses it must be covered by a rule; a page that keeps the icon in a
  separate file of its own isn't detected.
- Every run also breaks a copy of each source and built file, one rule's text
  at a time, and requires the check to report it, so a guard that stopped
  matching anything would fail rather than pass.

Run it after every Chromium upgrade build, as the
[upgrade procedure](../../Engine/README.md#upgrading-chromium) says. A failure
names the resource and rule; refit the rule's text or count in
`webui_branding_rules.h` and, if a page moved its logo, the list in `check.py`.
