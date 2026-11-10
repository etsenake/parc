# Native macOS helper routing and startup policy

The production entry leaves `CefSettings.browser_subprocess_path` empty so
CEF/Chromium selects Default, Renderer, GPU and Alerts helpers from the bundle.
The supplied helper path still receives absolute-path and executable checks.
The dedicated CDM helper retains the sandbox and signing policy described in
[engine policy](../../docs/engine-flags.md#library-validation).

## Startup policy

The real CEF application callback invokes `ApplyNativeStartupPolicy`. It disables
the bundled developer field-trial configuration and applies Parc's feature
policy. Explicit feature-list entries keep their state except for the accepted
product exclusions. The regression covers ordinary names, `*Name`,
`Name<Study.Group`, `Name:params` and surrounding whitespace using Chromium's
actual FeatureList precedence.

Both engine configurations also set `disable_fieldtrial_testing_config=true`;
packaging verifies the generated buildflag. With that configuration excluded,
Chromium refuses `--enable-field-trial-config`. Aperitif otherwise retains its
upstream default; this is not a separate helper-parity project.

The complete enabled/disabled feature lists and page-translation policy live in
[engine flags](../../docs/engine-flags.md#runtime-features).
Certificate Transparency enforcement is enabled through the non-Google-branded
opt-in. Chromium registers the PKI Metadata updater during browser startup
unless component updates are disabled. CT log data older than 70 days follows
Chromium's stale-list policy; Parc does not replace that owner.

## Focused regression

```sh
python3 tests/NativeHelperRouting/run.py /absolute/chromium/src --results /absolute/private/results
```

The runner reads generated Objective-C++ flags and links completed upstream
objects/components. It exercises the real `CefCommandLineImpl`,
`base::CommandLine`, FeatureList, CEF utility routing and
`ChildProcessHost::GetChildPath`. Cases cover both production and test executable
names, Default/Renderer/GPU paths, Alerts/CDM derivation and framework/resources.
The old explicit override is a negative control: it routes Renderer/GPU to the
default helper.

The runner records its commands and input identities in the requested private
output directory. It does not run GN/Ninja, initialize CEF, create a browser or
Profile, or launch a helper. Compatible completed component-engine objects are
required. Source-level integration checks remain in `tests/EngineSource`.
