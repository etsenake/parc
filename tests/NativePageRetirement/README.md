# Selected-page retirement regressions

This target exercises the production `RequestTabRetirement` coordinator and the actual pinned Chromium `UnloadController`, `TabStripModel`, `TabInterface` and `WebContents`. The fixture injects confirmations only through the public `TabUnloadHandler` interface. It does not duplicate the transaction state machine. It does not initialize CEF, payment, network, Keychain or a user profile.

The contract is all-document preflight, then a synchronous model validator, then exact lease revalidation, then posted unload. A Stay or invalidation before commit leaves every transaction-owned page intact. The model completion is asynchronous and successful only after all original contents are destroyed. Independent external destruction/navigation/transfer is not rollbackable; it terminates the transaction without reconstructing pages or unloading replacement documents. Outstanding replies are scoped to the actual WebContents and unique request token, including after a move between Browsers. Cross-document navigation and renderer loss retire that reply neutrally so a recovered page can be closed later. Individual/window/app closes cannot steal the same pending callbacks.

Beforeunload retains the exact page and completion through the native delegate
([dialog contract](../NativeJavaScriptDialogs/README.md)). The all-document
reservation and model validation adapt the pinned Chromium controller.
Automatic archive must recheck model state and actual native protection before
this irreversible boundary.

## Integration

- The overlay maps `tab_retirement.h/.cc` and `unload_transactions.h/.cc` to `//parc/native`; the production `BUILD.gn` defines their shared `tab_retirement` and `unload_transactions` source sets.
- The overlay compiles `native_page_retirement.mm` in the production `//parc:browser` mac source list with `//parc/native:tab_retirement` in its deps. The canonical public bridge category and application/page changes are part of the same cohort.
- The test BUILD/source map to `//parc/tests/native_page_retirement`, with the `unit_tests` source set registered in `//chrome/test:unit_tests` under `is_mac`.
- The transaction state, pending replies and posted algorithms live in `unload_transactions.cc`. `native-page-retirement.patch` leaves `unload_controller.h` pristine and keeps only `.cc` gates at the same close paths, plus the controller's unclosable-app policy and beforeunload runner handed to Parc at construction. The fixture installs the same hooks as the main delegate before its first Browser exists. The posted empty-Browser destruction keeps Chromium's `SynchronouslyDestroyBrowser`, whose `DeleteBrowser` hook drains native hosts first.

After normal generation, build `unit_tests` and run:

```sh
out/Release_GN_arm64/unit_tests --gtest_filter=NativePageRetirementTest.*
```

## Coverage

The source cases cover a later Stay, every approval preceding unload, late cancellation replies, moved-page reply ownership, renderer crash/retry on the same WebContents, prepared/committed document replacement, committed transfers, overlapping window close, duplicates/nonmembers, synchronous custom confirmation, untouched peers, an empty set still requiring model validation, validator reentry, actual destruction completion and sequential cross-Browser prompts.

The overlay includes the production source set and test target. The fixture
exercises Chromium retirement ownership with injected public confirmation
callbacks; renderer dialog presentation belongs to the connected native dialog
service.
