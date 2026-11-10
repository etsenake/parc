# Selected-page retirement regressions

This target exercises the production `RequestTabRetirement` coordinator and the actual pinned Chromium `UnloadController`, `TabStripModel`, `TabInterface` and `WebContents`. The fixture injects confirmations only through the public `TabUnloadHandler` interface. It does not duplicate the transaction state machine. It does not initialize CEF, payment, network, Keychain or a user profile.

The contract is all-document preflight, then a synchronous model validator, then exact lease revalidation, then posted unload. A Stay or invalidation before commit leaves every transaction-owned page intact. The model completion is asynchronous and successful only after all original contents are destroyed. Independent external destruction/navigation/transfer is not rollbackable; it terminates the transaction without reconstructing pages or unloading replacement documents. Outstanding replies are scoped to the actual WebContents and unique request token, including after a move between Browsers. Cross-document navigation and renderer loss retire that reply neutrally so a recovered page can be closed later. Individual/window/app closes cannot steal the same pending callbacks.

Beforeunload retains the exact page and completion through the native delegate
([dialog contract](../NativeJavaScriptDialogs/README.md)). The all-document
reservation and model validation adapt the pinned Chromium controller.
Automatic archive must recheck model state and actual native protection before
this irreversible boundary.

## Integration

- Map `tab_retirement.h/.cc` to `//cef/libcef/browser/parc_native` and import `tab_retirement.gni` from that directory's `BUILD.gn` (or append its exact source_set there).
- The overlay compiles `native_page_retirement.mm` in the production `libcef_static` mac source list with `//cef/libcef/browser/parc_native:tab_retirement` in its deps. The canonical public bridge category and application/page changes are part of the same cohort.
- The test BUILD/source map to `//cef/tests/parc_native_page_retirement`, with the `unit_tests` source set registered in `//chrome/test:unit_tests` under `is_mac && enable_cef`.
- `native-page-retirement.patch` owns both contextual UnloadController changes and retains the earlier `RequestBrowserDeletion` drain gate. Every target remains bound to its pinned original and final SHA-256.

After normal generation, build `unit_tests` and run:

```sh
out/Release_GN_arm64/unit_tests --gtest_filter=NativePageRetirementTest.*
```

## Coverage and evidence boundaries

The source cases cover a later Stay, every approval preceding unload, late cancellation replies, moved-page reply ownership, renderer crash/retry on the same WebContents, prepared/committed document replacement, committed transfers, overlapping window close, duplicates/nonmembers, synchronous custom confirmation, untouched peers, an empty set still requiring model validation, validator reentry, actual destruction completion and sequential cross-Browser prompts.

The 19 test cases were checked with actual generated pinned-Clang production and `unit_tests` flags via a VFS overlay. The source-set graph and linked test execution remain pending integration. Renderer beforeunload dialogs, AppKit sheets, transfer during renderer unload, browser/profile service drains and real multiwindow archive behavior still require linked/browser runtime tests. These compiler results do not assert those tests passed.
