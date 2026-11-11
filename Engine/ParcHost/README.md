# Chromium source overlay

`overlay.json` is the canonical reviewed source manifest for Parc's pinned
Chromium workspace. It records owned source inputs, patch preimages and patched
output hashes. Startup files install under `parc/`, native services under
`parc/native/` and native component tests under `parc/tests/`. Media, Blink and
FairPlay files that need a layer's internals install inside that layer, and
Parc's regression suites for Chromium code install in each layer's `parc_tests`
folder ([layout](../../docs/chromium-seams.md#where-the-code-lives)). Each patched
target appears once unless reviewed patch entries form a hash-verified sequence.

Use the commands in [Engine](../README.md) and
[development setup](../../docs/development-setup.md). Edit repository inputs,
never generated engine copies. Only the overlay integrator edits manifest
contents; renaming the manifest preserves its bytes and receipt identity.

Production native windows and their [component checks](../../tests/EngineConformance/native-window/README.md)
use Chromium directly. Keep component builds beside their sibling libraries.
Engine operations require the assigned owner's authorization, as described in
[the working contract](../../AGENTS.md).
