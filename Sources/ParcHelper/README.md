# Chromium subprocess helper

`Parc Helper` starts Chromium child processes inside the app's bundled engine
framework. Chromium chooses the helper bundle for each process role and gives
it the command line. The helper handles process entry. Browser startup and the
AppKit window lifecycle belong to the engine and the [app shell](../Parc/README.md). How it fits with the other libraries is in the [app architecture guide](../../docs/app-architecture.md).

## Entry point

[main.cc](main.cc) checks that Chromium's Apéritif library initialized before
entering `main`. Apéritif sets up the allocator zone and required sandbox
before the helper loads the engine. The helper locates the framework relative
to its own executable, opens it with `dlopen`, and passes its arguments to
`parc_engine_execute_process`.

The app-side [engine bridge](../ParcEngine/ParcEngine.m) checks the bundled
default helper during startup. Chromium routes child processes to the
appropriate helper, and the engine handles their communication with the browser
process after entry. The helper contains no Swift or AppKit window code.

## Build and packaging

The [source overlay](../../Engine/ParcHost/overlay.json) places this source and
its [GN target](../../Engine/ParcChromium/helper/BUILD.gn) into the pinned engine
tree. GN builds `//parc/helper:parc_helper` in the engine output and links it
against Apéritif.

[package-app.sh](../../scripts/package-app.sh) calls
[build.py](../../scripts/build.py), which verifies the helper against the sealed
engine manifest and copies it into the Default, Renderer, GPU, Alerts, CDM
and Apéritif helper app bundles under `Contents/Frameworks`. Packaging gives
the bundles their own identities and signing configuration.

## Checks and guides

The [helper-routing check](../../tests/NativeHelperRouting/README.md) exercises
Chromium's process-path selection against completed component-engine objects.
It checks routing without starting the browser or launching a helper.

```sh
python3 tests/NativeHelperRouting/run.py /absolute/chromium/src --results /absolute/private/results
```

[Packaging tests](../../tests/Packaging/test_icons.py) cover copying the
GN-built executable into the app bundles:

```sh
python3 -m unittest discover -s tests/Packaging -p test_icons.py
```

See the [helper and signing contract](../../tests/Packaging/README.md#helper-and-signing-contract)
and [engine library validation](../../docs/engine-flags.md#library-validation)
for the bundle layout and sandbox boundaries.
