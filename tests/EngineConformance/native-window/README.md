# Native window association and modal host

This is a bounded component test, not a complete `BrowserWindow` or a replacement-engine demonstration. `Engine/ParcNative/browser_window.h/.mm` supplies a weak shell-window association and a real Chromium `WebContentsModalDialogHost` companion. The shell owns its `NSWindow`; neither component creates a Chrome window, `BrowserView`, hidden parking window or replacement page.

## Window and modal ownership

The shell supplies a weak NSWindow association. Close, key/resign and fullscreen
notifications are filtered by that exact owner; multiple Browser associations
may refer to one physical window. The BrowserWindow adapter arbitrates selection.

Both modal-host getters return the same companion. Its host view is the active
page's native superview, not the window content view. Positioning subtracts
separately truncated half-sizes: an 800-wide window and 301-wide dialog yield
x=250. Maximum size uses active content, falling back to the window frame.
Position and destruction observers may reenter. Remove each observer before its
terminal callback, and defer owner deletion until all callbacks finish.

## Executable AppKit checks

From the repository root:

```sh
bash tests/EngineConformance/native-window/run.sh
```

This compiles the actual Objective-C portion of `browser_window.mm` as Objective-C using Apple clang, ARC and warnings as errors. It creates ordinary, unshown test windows and tests native close delivery, attachment identity, weak observer/window ownership, notification filtering, idempotent and terminal teardown, reentrant reassociation/invalidation, independent associations on one window and rejection of off-main-thread calls. It does not launch Parc or another browser, load a profile, show a fullscreen window or synthesize keyboard focus. Key/fullscreen notification routing is tested by posting named notifications.

The AppKit suite covers 60 assertions across five groups. The modal companion removes each observer before its terminal callback, preserving active outer iterators and allowing a callback to release its observer.

## Actual Chromium syntax checks

After the pinned engine checkout has completed its normal project generation and prerequisite generated headers exist:

```sh
python3 tests/EngineConformance/native-window/check-chromium.py /absolute/path/to/chromium/src
```

The check reads the generated `ui/gfx` ObjC++ flags for the implementation and `components/web_modal` unit-test flags for the test source. It uses that checkout's real compiler, Chromium headers, generated headers and C++ library headers. It invokes neither GN nor Ninja, uses no substitute headers, and writes reports only under the repository's ignored `build/tests/native-window/`. Syntax checking does not link or execute the C++ companion.

`ModalHostTests.mm` contains seven real GoogleTest cases for active-view identity changes, odd and oversized dimensions, maximum-size changes, observer addition/removal boundaries, nested invalidation, observer release during destruction, destruction notification and invalidation before delegate destruction. The included `BUILD.gn` defines a runnable `parc_native_window_tests` target with the normal Chromium test entry point (`//base/test:run_all_unittests`), actual `web_modal`/`base`/`gfx` libraries, GoogleTest and AppKit. It requires no Browser, renderer, browser profile or full-browser test suite.

The overlay maps these files relative to `chromium/src`:

| Repository file | Overlay target |
|---|---|
| `Engine/ParcNative/BUILD.gn` | `parc/native/BUILD.gn` |
| `Engine/ParcNative/page_host.h` | `parc/native/page_host.h` |
| `Engine/ParcNative/page_host.mm` | `parc/native/page_host.mm` |
| `Engine/ParcNative/browser_window.h` | `parc/native/browser_window.h` |
| `Engine/ParcNative/browser_window.mm` | `parc/native/browser_window.mm` |
| `tests/EngineConformance/native-window/ModalHostTests.mm` | `parc/tests/parc_native_window/ModalHostTests.mm` |
| `tests/EngineConformance/native-window/BUILD.gn` | `parc/tests/parc_native_window/BUILD.gn` |

The overlay installs the
`//parc/tests/parc_native_window:parc_native_window_tests` target definition.
No loaded build file depends on it, so GN does not generate it and neither the
normal engine build nor the Chrome test binaries include it. Running the target
first requires connecting it from a loaded build file, regenerating and
building it explicitly. It depends on `//parc/native:native_components`,
compiling the actual page/window/modal sources with Chromium's default ARC and
warning policy. Once available, the executable runs from the engine output
directory using the normal generated component-library paths:

```sh
./parc_native_window_tests --gtest_filter=NativeModalDialogHostTest.*
```

The checker reads existing generated targets and leaves the engine checkout unchanged.
The production [native window adapter](../../../Engine/ParcNative/native_browser_window.mm)
uses this companion for page-owned modal presentation; the
[window guide](../../../docs/windows-lifecycle.md) owns the shell lifecycle contract.
