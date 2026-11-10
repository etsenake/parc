# Native macOS helper routing and startup policy

The production entry leaves `CefSettings.browser_subprocess_path` empty so pinned
CEF/Chromium selects Default, Renderer, GPU and Alerts helpers from the standard
CEF bundle. The supplied helper path still undergoes absolute-path validation,
and the production facade checks its executable before startup. Sandbox and
signing policy are unchanged.

The used `ApplyNativeStartupPolicy` helper adds
`--disable-field-trial-config` in the real CEF application callback. Chromium's
[`testing/variations/README.md`](https://chromium.googlesource.com/chromium/src/+/d0c02bfad08ec92a6ffcf989e53cd995e6381a4c/testing/variations/README.md)
explicitly recommends this control for non-Chrome browsers. This disables the
bundled developer test configuration by default; it does not permanently disable
Aperitif or replace ordinary feature defaults. The existing product feature
exclusions, explicit feature switches and launch arguments are preserved.
Explicit developer test opt-ins retain upstream precedence. Both engine
configurations now also set the `disable_fieldtrial_testing_config=true` GN
policy that pinned CEF `tools/gn_args.py` supplies for `is_official_build`, and
`scripts/build.py` verifies its generated `FIELDTRIAL_TESTING_ENABLED=0`
buildflag before packaging. With the config excluded, upstream precedence for
`--enable-field-trial-config` is Chromium's startup refusal; this switch then
only guards engines built before that source lock.

The same callback applies Parc's startup feature defaults.
It enables
`CertificateTransparencyAskBeforeEnabling`, the opt-in that turns on
Certificate Transparency enforcement in non-Google-branded builds
(`SystemNetworkContextManager::IsCertificateTransparencyEnabled`). It disables
`MacAppCodeSignClone` and `MacAppCodeSignCloneRenameAsBundle` (no launch-time
bundle clone and no cleanup helper at quit), `FedCm`,
`AutofillServerCommunication`, `PreloadMediaEngagementData`, `BrowsingTopics`,
`NetworkTimeServiceQuerying`, `LiveCaption`, `MerchantTrust`,
`PageInfoAboutThisSite`, `PageInfoAboutThisSiteMoreLangs` and
`TailoredSecurityIntegration`. Each name matches its `BASE_FEATURE` definition in
the pinned Chromium source. Chromium registers `--disable-features` before
`--enable-features` and keeps the first entry for a feature, so a disable would
override an explicit enable. These states are defaults: a feature the
command line already names in either list, including the `*Name`,
`Name<Study.Group` and `Name:params` forms with whitespace around the name
trimmed as Chromium does, keeps its explicit state. The product
exclusions are still applied over explicit enables. They are the
history-embedding model, the excluded Chromium AI group (`Glic`, `GlicActorUi`,
`AutofillActorMode` and `LensOverlay`) and the translate ranker
(`TranslateRankerQuery`, `TranslateRankerEnforcement`), all Josh's decisions of
November 1. Pinned CEF already disables `GlicActorUi`, `AutofillActorMode` and
`LensOverlay` in the browser process; listing them keeps them off for an
explicit enable too. The on-device omnibox head model is no longer excluded: it
arrives through the component updater and needs no Google API key.

Parc adds one default of its own the same way: `WebContentsDiscard`, the
in-place discard behind `-[PCNativePage discardIfIdle]`, which frees a
long-unused background tab's renderer while keeping its page and WebContents.

Page translation is excluded because Chrome's translate service needs a Google
API key, which Parc never ships. The callback adds `--disable-translate-trigger`,
which makes `TranslateManager::ComputePossibleOutcomes` prevent every automatic
offer before the ranker is queried. With both ranker features off,
`TranslateRankerImpl` creates no model loader, so the ranker model is never
downloaded. Page language detection is unchanged; Autofill and other features
still read it. The remaining translation entry points are closed in their own
source and listed in [engine flags](../../docs/engine-flags.md#page-translation).

CT enforcement
fails open once the CT log list is more than 70 days old
(`ChromeCTPolicyEnforcer`). Chrome's startup registers the PKI Metadata
component that refreshes the list unless `--disable-component-update` is
present; whether it updates in Parc has not been observed.

The regression executes the used policy against the actual `CefCommandLineImpl`
and `base::CommandLine`, including explicit opt-ins in each feature-list form.
It initializes a separate real `base::FeatureList` from the resulting switches
to confirm Chromium's precedence. It then calls completed CEF `util_mac.o`/`cef_switches.o`
and Chromium's `ChildProcessHost::GetChildPath`. It checks both executable names,
`Parc` and `parc_native_runtime_tests`, including base/Renderer/GPU routing,
CEF Alerts and CDM derivation and framework/resource paths. The CDM line was
added with overlay 289 and hasn't run yet. It also reproduces the old
explicit override returning the default helper for Renderer/GPU. The Alerts
client override is source-verified; a full Chrome browser client is not created.

```sh
python3 tests/NativeHelperRouting/run.py /absolute/chromium/src --results /absolute/private/results
```

The runner reads actual `libcef_static.ninja` Objective-C++ flags, links completed
upstream objects/components, records input hashes and executes only this focused
check. It never invokes GN/Ninja, initializes CEF, creates a browser/profile or
launches a helper. Compatible completed engine output is required. There are no
fake headers or copied routing/command-line implementations.

revision, and the changed application callback passed pinned `libcef_static`
has 42 assertions. It and the production callback with the revised policy pass
the same syntax-only check. They have not been linked or run, because the
completed engine output was being rebuilt.
The focused link warns that the optional LLVM LTO library is absent; the
component loader also reports the existing duplicate `ANGLESwapCGLLayer` class
in `libblink_modules`/`libgl_init`. Neither invalidates these command/routing
results. Actual browser startup, graphics, sandbox/JIT, notifications and clean
shutdown remain package/runtime gates. Complete Aperitif helper architecture and
