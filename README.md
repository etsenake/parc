# Parc

Parc is an independent native macOS browser with Spaces, pinned tabs, automatic
archiving, split views, extensions, local Easels and Notes, capture tools and
customizable themes. Its Swift/AppKit application uses a source-owned Chromium

## Install

```sh
brew tap etsenake/tap
brew install --cask parc
```

Upgrade with `brew upgrade --cask parc`. Signed, notarized releases are published
at [parc-releases](https://github.com/etsenake/parc-releases/releases).

## Product and documentation

- [Product status and scope](docs/parity.md): capabilities and current delivery
  state, including Parc additions.
- [Backlog](docs/backlog.md): remaining work and explicit deferrals.
- [Documentation index](docs/README.md): focused product and engineering guides.
- [Working contract](AGENTS.md) and [collaboration](docs/collaboration.md).

## Build

Development requires an Apple Silicon Mac, full Xcode and Python 3.12 or later.
Start with [developer onboarding](docs/developer-onboarding.md). Restore the saved
[engine workspace](docs/engine-artifacts.md) to preserve compiled objects and
caches before considering a fresh Chromium build.

- [Development setup](docs/development-setup.md): prerequisites and commands.
- [Engine integration](Engine/README.md): pinned dependencies and source overlays.
- [Application packaging](tests/Packaging/README.md): native app, helpers and assets.
- [Production release](docs/master-release.md): build, sign, notarize, publish
  GitHub assets and update the Homebrew cask. Installation is manual.

Component development packages require their sibling engine libraries. Official
non-component releases carry the engine inside `Parc.app` and install on their own.

## Repository

- `Sources/ParcApp`: native windows and interface.
- `Sources/ParcCore`: browser state, persistence and application behavior.
- `Sources/ParcEngine`, `Engine/ParcNative`: app bridge and Chromium integration.
- `Engine/ParcHost`: source overlays for the pinned engine.
- `Resources`: bundled assets.
- `tests`, `scripts`: focused checks and reusable build tooling.

Build products, profiles, logs and dependency binaries stay in ignored local
storage. Git contains used source, focused checks and current documentation.
