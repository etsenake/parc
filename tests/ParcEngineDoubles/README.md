# Engine doubles for Swift app tests

`ParcEngineDoubles` gives the Swift app tests native class symbols and
controllable Objective-C fixtures. It lets the application libraries load and
exercise their engine-facing code without a built Chromium framework.
Chromium itself and its end-to-end checks live under [Engine](../../Engine/README.md)
and the relevant component test folders. The rules every test follows, and the kinds of test that are banned, are in the [testing guide](../../docs/testing.md).

## Entry points

- [EngineDoubles.m](EngineDoubles.m) defines the native class symbols the app
  libraries reference. It includes [command-bar search doubles](CommandBarSearchDoubles.inc)
  and [the shortcut command double](ShortcutCommandDouble.inc).
- [ImportEngineDoubles.h](ImportEngineDoubles.h) exposes import data and
  sessions for browser-import tests.
- [EaselEngineDoubles.h](EaselEngineDoubles.h) supplies native page doubles for
  the Easel page pool. [RenderFrameEngineDoubles.h](RenderFrameEngineDoubles.h)
  helps drive render-frame delivery.
- [ToolbarEngineDoubles.h](ToolbarEngineDoubles.h) supplies the toolbar
  engine fixture. [MiniPlayerEngineFixture.h](MiniPlayerEngineFixture.h)
  provides a configurable source for Mini Player tests.

## Dependencies and consumers

[Package.swift](../../Package.swift) makes this a Clang target and gives it
access to the app bridge and engine headers. [ParcTests](../ParcTests/README.md)
links it alongside the app libraries. The optional site-film harness targets
also depend on it. The Swift tests get preferences and UI helpers from
[ParcTestSupport](../ParcTestSupport/README.md) and
[ParcTests/Support](../ParcTests/Support). Their resource fixtures belong to
the test target. This target has no manifest resources.

The [stub generator](../../Plugins/GenerateEngineStub/GenerateEngineStub.swift)
keeps the committed engine text stub and generated class symbols in sync with
the bridge headers. See [the Swift package](../../docs/development-setup.md#the-swift-package)
for its command.

## Run the consumers

Exercise the doubles through their app suites. From the repository root:

```sh
swift test
swift test --filter MiniPlayer
swift test --filter EaselPagePool
```

The [facade test targets](../EngineFacadeTests) have their own native doubles
and can run independently. See [Chromium seams](../../docs/chromium-seams.md#parc-owned-test-targets),
[embedded pages](../../docs/embedded-pages.md) and
[Mini Player](../../docs/media-mini-player.md) for the boundaries the fixtures
exercise.
