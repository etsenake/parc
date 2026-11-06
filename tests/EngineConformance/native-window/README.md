# Native window association and modal host

This is a bounded component test, not a complete `BrowserWindow` or a replacement-engine demonstration. `Engine/ParcNative/browser_window.h/.mm` supplies a weak shell-window association and a real Chromium `WebContentsModalDialogHost` companion. The shell owns its `NSWindow`; neither component creates a Chrome window, `BrowserView`, hidden parking window or replacement page.

## Reference and adaptation


- A custom `arc::browser::ui::Window` associates a supplied weak `NSWindow`; its native tracker registers close, key/resign-key and enter/exit-fullscreen notifications (`0xa888fb8`, close handler `0xa8892d0`). The app cache has separate window and profile/context identities. Multiple associations can consequently refer to one shell window; activation arbitration remains the future adapter's responsibility.
- Both modal-host getters (`0x68a8860`, `0x68a88f4`) return the same companion at Window+`0x1d0`. Host-view resolution (`0x68a9f7c` → `0xa89d188`) queries the actual active page's native superview. The future adapter must supply that wrapper, not `NSWindow.contentView`.
- Primary positioning (`0x68a9d30`) subtracts separately truncated dialog half-sizes from window half-sizes. An 800-wide window and 301-wide dialog produce x=250. Oversized dialogs are not clamped in that method. Maximum size (`0x68a9f30`) comes from active content, falling back to the associated window frame. The delegate supplies those dimensions; no origin/coordinate conversion is guessed here.
- The reference has an additional, differently positioned host method whose name/caller selection is unresolved. This implementation does not invent an equivalent API. The activation/constrain results are true in the corresponding interface neighborhood, with that identification an interface-based inference rather than recovered symbols.


## Executable AppKit checks

From the repository root:

```sh
bash tests/EngineConformance/native-window/run.sh
```


The current AppKit run passes **60 assertions across five groups**. The actual Chromium implementation and all seven modal-test cases pass compilation with warnings treated as errors. A private executable linked against the completed v49 component libraries passes all seven cases with the v50 source fix. The first linked v49 run exposed a real nested-invalidation failure: clearing the checked-observer list marked an already-removed observer twice. Version 50 removes each observer before its terminal callback, preserving any active outer iterator and allowing a callback to release its observer. The integrated v50 rebuild subsequently succeeded, and its generated executable also passes all seven tests. Real browser/dialog checks remain pending.

## Actual Chromium syntax checks

After the pinned engine checkout has completed its normal project generation and prerequisite generated headers exist:

```sh
python3 tests/EngineConformance/native-window/check-chromium.py /absolute/path/to/chromium/src
```

The check reads the generated `ui/gfx` ObjC++ flags for the implementation and `components/web_modal` unit-test flags for the test source. It uses that checkout's real compiler, Chromium headers, generated headers and C++ library headers. It invokes neither GN nor Ninja, uses no substitute headers, and writes reports only under the repository's ignored `build/tests/native-window/`. Syntax checking does not link or execute the C++ companion.

`ModalHostTests.mm` contains seven real GoogleTest cases for active-view identity changes, odd and oversized dimensions, maximum-size changes, observer addition/removal boundaries, nested invalidation, observer release during destruction, destruction notification and invalidation before delegate destruction. The included `BUILD.gn` defines a runnable `parc_native_window_tests` target with the normal Chromium test entry point (`//base/test:run_all_unittests`), actual `web_modal`/`base`/`gfx` libraries, GoogleTest and AppKit. It requires no Browser, renderer, browser profile or full-browser test suite.

Version 2 of the reviewed overlay maps these files relative to `chromium/src`:

| Repository file | Overlay target |
|---|---|
| `Engine/ParcNative/BUILD.gn` | `cef/libcef/browser/parc_native/BUILD.gn` |
| `Engine/ParcNative/page_host.h` | `cef/libcef/browser/parc_native/page_host.h` |
| `Engine/ParcNative/page_host.mm` | `cef/libcef/browser/parc_native/page_host.mm` |
| `Engine/ParcNative/browser_window.h` | `cef/libcef/browser/parc_native/browser_window.h` |
| `Engine/ParcNative/browser_window.mm` | `cef/libcef/browser/parc_native/browser_window.mm` |
| `tests/EngineConformance/native-window/ModalHostTests.mm` | `cef/tests/parc_native_window/ModalHostTests.mm` |
| `tests/EngineConformance/native-window/BUILD.gn` | `cef/tests/parc_native_window/BUILD.gn` |


```sh
./parc_native_window_tests --gtest_filter=NativeModalDialogHostTest.*
```

Project generation with overlay version 2 has passed. A separate pinned-Clang syntax check of the installed `page_host.mm`, `browser_window.mm` and `ModalHostTests.mm`, using their own newly generated target flags, also passes. This verifies the new targets' compiler configuration in addition to the prerequisite-based checker above. The complete v49 engine build linked this target successfully. The corrected v50 private executable has also linked and executed all seven cases against those genuine Chromium libraries.

Root integration owns the source-overlay/GN changes; these test files do not mutate or generate the external checkout. Real browser/dialog presentation, resize/selection notifications, focus arbitration, multi-profile teardown and beforeunload coordination are still required. The passing component tests do not establish those integrated behaviors.
