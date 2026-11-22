# Native component header shims

`ParcNativeShims` supplies include paths for the SwiftPM build of the Parc-owned
native components. It is the public headers directory of the `ParcNative`
target. The headers here forward to checked-in native interfaces. Production
implementations stay under [Engine/ParcNative](../../Engine/ParcNative), and
test behavior lives in [ParcNativeTests](../ParcNativeTests/README.md). The rules every test follows, and the kinds of test that are banned, are in the [testing guide](../../docs/testing.md).

## Entry point

[ui/base/cocoa/content_drop_router.h](ui/base/cocoa/content_drop_router.h)
lets the package resolve the Chromium-style include path for the
[Parc-owned content drop router header](../../Engine/ParcNative/content_drop_router.h).
It forwards the declaration from its owner so the package can compile against
the same interface as the native source.

The [content drop router suite](../ParcNativeTests/Routing/ContentDropRouterTests.mm)
exercises that boundary. The production [app bridge](../../Sources/ParcEngine/ParcEngine.h)
also exposes the native content drop interfaces to Swift.

## Dependencies and consumers

[Package.swift](../../Package.swift) compiles `ParcNative` from the explicitly
listed native sources and supplies the include search paths. It sets this folder
as `publicHeadersPath`. The dependent [native XCTest target](../ParcNativeTests/README.md)
offers its own offscreen window and clock helpers in
[Support](../ParcNativeTests/Support). The shims have no separate resources or
test target. Fixture resources are declared on the native XCTest target.

For the [native test harness](../ParcNativeTests/README.md#dependencies-and-helpers)
and [native fixture resources](../ParcNativeTests/README.md#bundled-fixtures),
see the consuming target's README. Swift-only helpers are in
[ParcTestSupport](../ParcTestSupport/README.md) and
[ParcTests/Support](../ParcTests/Support).

## Run the consumer

From the repository root:

```sh
swift test
swift test --filter ContentDropRouterTests
```

The filter selects the XCTest class named `ParcNativeTests_ContentDropRouterTests`
even though the filename omits the target prefix.

See the [testing guide](../../docs/testing.md#running-tests)
for package test commands and
[Chromium seams](../../docs/chromium-seams.md#parc-owned-test-targets)
for where to put engine code that builds without Chromium.
