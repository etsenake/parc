# Native component tests

`ParcNativeTests` exercises Parc-owned Objective-C and Objective-C++ engine
components through XCTest. It uses a SwiftPM library of selected
[Engine/ParcNative](../../Engine/ParcNative) sources and local test fixtures.
Checks requiring the Chromium build have their own runners outside this target. The rules every test follows, and the kinds of test that are banned, are in the [testing guide](../../docs/testing.md).

## Where the suites live

| Folder | Look here for |
| --- | --- |
| [Data](Data) | Keychain namespace, password files and private session ownership |
| [Dialogs](Dialogs) | Autofill, certificates, authentication, JavaScript dialogs, external protocols and permissions |
| [Extensions](Extensions) | Install, popup, side panel and uninstall presentation |
| [Media](Media) | Picture in picture, FairPlay policy and media state delivery |
| [Pages](Pages) | Page hosting, compositor, focus, find, DevTools, status and WebUI branding |
| [Routing](Routing) | Native content drops, Peek Escape, search and link routing |
| [Windows](Windows) | Picker reservations and window association |

## Dependencies and helpers

[Package.swift](../../Package.swift) builds the files in its
`nativeLibrarySources` list as `ParcNative` and uses
[ParcNativeShims](../ParcNativeShims/README.md) for its public headers.
The test target depends on that library and also has source header paths for
the native components it exercises.

[Support](Support) contains the native test harness.

- [ParcNativeTest.h](Support/ParcNativeTest.h) defines `ParcNativeTestCase` and
  `PARC_CHECK`.
- [ParcNativeWindows.h](Support/ParcNativeWindows.h) provides offscreen window,
  sheet and popover state for native presenters.
- [ParcNativeClock.h](Support/ParcNativeClock.h) provides controllable time and
  work queues. `ParcNativeAdvance` advances the clock and runs due work.
  `ParcNativeSettle` drains work already pending.

The Swift-specific helpers in [ParcTestSupport](../ParcTestSupport/README.md)
and [ParcTests/Support](../ParcTests/Support) belong to the Swift test targets.

## Bundled fixtures

The test target copies [certificate-fixture.pem](Dialogs/certificate-fixture.pem)
and [Monochrome.svg](Artwork/Monochrome.svg) as resources. Native tests read
them through `SWIFTPM_MODULE_BUNDLE`. The SVG comes from the checked-in app icon
marks through the [Artwork link](Artwork).

## Run the tests

Run from the repository root and filter by XCTest class or a shared class
prefix:

```sh
swift test
swift test --filter PageHostTests
swift test --filter VideoPiPWindowTests
```

See the [testing guide](../../docs/testing.md#native-tests),
[Chromium seams](../../docs/chromium-seams.md#parc-owned-test-targets),
[web interactions](../../docs/web-interactions.md) and
[media interactions](../../docs/media-interactions.md) for the test workflow
and native component boundaries.
