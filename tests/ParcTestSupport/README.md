# Shared Swift test support

`ParcTestSupport` gives the app and core test targets the same isolated
preference store. It is a support library in [Package.swift](../../Package.swift).
Feature fixtures, assertions and test cases stay with the test targets that
own them. The rules every test follows, and the kinds of test that are banned, are in the [testing guide](../../docs/testing.md).

## Entry point

[TestDefaults.swift](TestDefaults.swift) defines `TestDefaults`, a
`UserDefaults` subclass with a unique suite name and a lock-protected
in-memory store. It implements the ordinary typed preference accessors and
bridges arrays and dictionaries to property-list objects. On release it clears
any persistent values under its temporary domain.

A fixture passes a `TestDefaults` instance to the production initializer that
accepts `UserDefaults`. The test can then set preferences and inspect their
effects without affecting the real defaults. For call sites, see
[the Easel canvas fixture](../ParcTests/Support/TestEaselCanvas.swift) and
[the Notes folder preference suite](../ParcCoreTests/Notes/NoteFolderPreferencesTests.swift).

## Dependencies and consumers

The target imports Foundation. [ParcTests](../ParcTests/README.md)
and [ParcCoreTests](../ParcCoreTests/README.md) both link it.

## Fixtures by target

This support target has no bundled resources. The app suites use resources
such as [Notes fonts](../ParcTests/Notes/Fixtures), while the core suites
carry resources such as [Easel round-trip data](../ParcCoreTests/Easels/Fixtures/EaselRoundTrip).
Both sets are declared on their respective test targets in the manifest.

For app tests that need Notes files or AppKit clicks, see
[IsolatedNoteFiles.swift](../ParcTests/Support/IsolatedNoteFiles.swift) and
[ControlClick.swift](../ParcTests/Support/ControlClick.swift). Those helpers
live in [ParcTests/Support](../ParcTests/Support), where they can use that
target's AppKit and app library dependencies.

## Run the consumers

This library is compiled when its consumers run. Run from the repository root:

```sh
swift test
swift test --filter NoteFolderPreferencesTests
```

See the [testing guide](../../docs/testing.md#what-a-test-looks-like)
for how suites share helpers and stay isolated.
