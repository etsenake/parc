# Parc engine bridge

`ParcEngine` is the Objective-C module imported by Swift for the native browser
engine. It exposes the browser lifecycle and page view and adapts native
callbacks for AppKit clients. Chromium integration and engine-side behavior
live under [Engine](../../Engine/README.md). The app shell owns windows, tab
selection and higher-level presentation. How it fits with the other libraries is in the [app architecture guide](../../docs/app-architecture.md).

## Entry points

- [ParcEngine.h](ParcEngine.h) is the module's umbrella header. It declares
  `PCBrowserEngine`, `PCBrowserView`, `PCBrowserViewDelegate`, the extension
  import facade and `PCImportedSidebarFiles`, which decrypts a source
  browser's sidebar files off the main thread and reports an older engine as
  unable to, and imports the native AppKit, application and page-host
  interfaces from [Engine/ParcNative](../../Engine/ParcNative).
- [ParcEngine.m](ParcEngine.m) implements the lifecycle calls and
  wraps native page operations and delegate callbacks. Start here for engine
  startup results, shutdown, page navigation or media delivery at the
  Swift–native boundary.
- [VideoPiPWindow.h](VideoPiPWindow.h) and
  [VideoPiPWindow.m](VideoPiPWindow.m) expose and implement the AppKit video
  picture-in-picture presenter. The app's
  [application client](../Parc/AppDelegate.swift) creates and releases its
  windows through the native client interface.

## Build and callers

[Package.swift](../../Package.swift) compiles this folder as the `ParcEngine`
target and adds the native headers to its include path. Package builds
weak-link the committed [engine text stub](../../Stubs). App packaging uses
the package's objects, then [build.py](../../scripts/build.py) links the app
against the sealed engine framework. The Swift shell calls `PCBrowserEngine`
from [ParcLaunch](../Parc/ParcLaunch.swift) and [AppDelegate](../Parc/AppDelegate.swift).
Views and controllers in the feature libraries use `PCBrowserView` and the
native AppKit interfaces to interact with pages.

## Checks and guides

[EngineFacadeTests](../../tests/EngineFacadeTests) compile the facade against
native doubles for media delivery, extension import reports, sidebar file
decryption and compatibility
with older engine exports. [ParcNativeTests](../../tests/ParcNativeTests/README.md)
also exercise the picture-in-picture window. Run from the repository root:

```sh
swift test --filter EngineFacade
swift test --filter VideoPiPWindowTests
```

See [Chromium seams](../../docs/chromium-seams.md#where-the-code-lives) for
ownership at the engine boundary, [web interactions](../../docs/web-interactions.md)
for the page-facing behavior, and [media interactions](../../docs/media-interactions.md)
for the playback controls.
