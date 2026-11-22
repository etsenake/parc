# Parc executable entry point

`ParcMain` is the executable target behind the `Parc` SwiftPM product.
[main.swift](main.swift) enters the main actor and calls `ParcLaunch.run()`.
Application setup, the main loop and shutdown live in the
[Parc app library](../Parc/README.md), so unit tests can import the application
code without executing the launcher. How it fits with the other libraries is in the [app architecture guide](../../docs/app-architecture.md).

## Launch path

Follow [ParcLaunch.swift](../Parc/ParcLaunch.swift) from the call in
`main.swift`. There the shell creates `ParcApplication`, installs
[AppDelegate](../Parc/AppDelegate.swift) and asks it to prepare startup.
When preparation succeeds, the shell queues the first window, runs the browser
main loop through [ParcEngine](../ParcEngine/README.md), and finishes shutdown
when the loop returns. Preparation can also return an exit code directly.

Use the app library if a launch change needs to decide which profile, restored
window or onboarding step to open. Use the engine bridge for the call into the
native startup code. This folder is the handoff between the executable and the
app library.

## Build and dependencies

[Package.swift](../../Package.swift) declares `ParcMain` with dependencies on
`Parc` and `ParcEngine`. The executable's run path points at the app bundle's
`Frameworks` directory. [build.py](../../scripts/build.py) builds the Swift
package and links its objects against the sealed engine and Sparkle to write
`Contents/MacOS/Parc`.

For compile-check commands and the difference between a package build and app
packaging, see [development setup](../../docs/development-setup.md#check-swift-without-building-an-engine-or-app).

## Checks and guides

The launcher has no separate test target. The
[app tests](../../tests/ParcTests/README.md) cover the shell and
[core tests](../../tests/ParcCoreTests/README.md) cover its underlying state.
For example, the Dock reopen decision has a focused model suite:

```sh
swift test --filter DockReopenTests
```

See [window lifecycle](../../docs/windows-lifecycle.md#restoration-and-launch-continuity)
for launch and restoration, [onboarding](../../docs/onboarding.md) for
first-launch setup, and [packaging](../../tests/Packaging/README.md) for the
executable's place in the signed app bundle. The
[production release guide](../../docs/master-release.md#pipeline) describes
how the packaged executable reaches a release.
