# Parc



## Scope



The [parity ledger](docs/parity.md) is the sole current record of progress, priorities, remaining work, explicit user requests and evidence. A successful build does not establish experience parity.

## Build

Local development requires an Apple Silicon Mac, Xcode with Swift and Python 3.12 or later. Restore the saved Chromium workspace to keep its existing compiled objects and build cache. The last completed app-and-engine package is available separately. See the [engine artifact guide](docs/engine-artifacts.md).

- [Production release command](docs/master-release.md): one command for engine, app, signing, notarization, GitHub, installation and Homebrew.
- [Engine source and native integration](Engine/README.md): pinned dependencies, source workspace, reviewed integration and engine build commands.
- [Application packaging](tests/Packaging/README.md): seal a completed engine, compile the native app and package its helper processes, resources and icons.
- [Working contract](AGENTS.md): implementation, reverse engineering, coordination and repository rules.

Component development packages contain `Parc.app` alongside required engine libraries; keep that directory together. Official non-component shipping packages carry the engine inside `Parc.app` and install on their own. Packaging preserves upstream engine load commands and signs copied code normally.

## Repository

- `Sources/ParcApp`: native application windows and interface.
- `Sources/ParcCore`: local browser state, persistence and application behavior.
- `Sources/ParcEngine` and `Engine/ParcNative`: the application-to-engine bridge and native Chromium integration.
- `Engine/ParcHost`: reviewed source overlays for the pinned upstream engine.
- `Resources`: bundled artwork, icons, audio and other app assets.
- `tests` and `scripts`: focused checks and reusable build tooling.

Build products, dependency binaries, profiles, logs and raw reverse-engineering output are local ignored artifacts. Git contains production source, focused checks and useful documentation.
