# Live tab transfer checks

`NativeTabTransferTest.*` exercises the production `TransferLiveTab` function with actual Chromium Browser, TabStripModel, TabInterface, WebContents and UnloadController instances. Its twenty-two cases cover identical tab/page pointers, empty and nonempty destination selection, ordinary popup owners, cross-profile and unsupported owner refusal, last-source rollback, original pin/group/opener restoration on rollback, untouched and rolled-back preexisting-empty-owner preservation, explicit close ordering, owner-refill checks, failed source reattachment, callback-driven ownership changes, real close reservations, nested transfer and independent page destruction. The presentation callback stands in only for AppKit attachment; it does not implement tab ownership or close logic.

The shared `tab_transfer` source set is consumed by both libcef_static and the test-only target, avoiding a libcef_static dependency from chrome/test:unit_tests. After the reviewed overlay is applied and built, run `unit_tests --gtest_filter='NativeTabTransferTest.*'`. Source checks against the pinned compiler and actual generated controller/libcef/unit_tests settings pass. These tests have not yet been linked or executed. Actual renderer/CEF ownership, extension tab identity, DOM state, posted native callbacks, focus, visibility and cross-window presentation require the independent-engine runtime gate.

## Native shell contract

`PCNativeBrowserWindow.transferPage(_:profilePath:container:completion:)` moves the exact page to the destination's actual Profile Browser. When absent, it constructs an empty native Browser through the real typed factory; it never creates a blank/replacement WebContents. Source and destination must be different physical registered windows with the same actual Profile. Normal and ordinary popup Browsers are supported. DevTools, document-PiP and app-specific owners remain refused until their separate ownership paths are integrated.

Before calling, reserve both shell ownership claims and attach a temporary plain NSView to the destination NSWindow. Keep the original PCBrowserView and its single PCNativePage observer alive. Pass the temporary view as the native transfer container. On genuine Transferred completion, move that same PCBrowserView to the destination, install the new owner/model claim and use the normal pageDidAttach path for its final container. Do not create a second adopting wrapper, call closeBrowser, navigate a URL, or let queued reconciliation adopt the same page again. Selection of a nonempty destination remains a separate explicit shell action.

Refused leaves the source unchanged. Restored means the actual tab was put back in its surviving source after attachment failed; the shell retains the source claim. Interrupted reports independent external page/owner mutation, requiring exact-identity reconciliation, never saved-URL reconstruction. Such independent destruction cannot be rolled back. Completion is posted, with native window/app close and another transfer blocked through result callback delivery. Ordinary native page close is blocked during the synchronous ownership change.



## Reference and verification boundary

`97df76204405d2046261e9f8efeb0cb84f74bf9c223b81f3567e6087b52967a8`:
transfer entry `0x68b6918` reaches `0x685ebe0`, which preserves the detached
TabModel/WebContents, rejects mismatched contexts, clears/rebinds page delegate
ownership and activates an empty destination. It does not recreate the page from
its URL or preserve source pin/group flags as destination insertion flags.
Current Chromium owns those delegate transitions through its actual tab-strip
callbacks; rollback restores surviving source pin/group/opener state.

Version 36 source-connects the native bridge and shared controller/test targets.
Read-only replay validates 103 mapped files and 98 patched targets. Five combined
compiler checks pass with existing pinned generated settings; new target
header-dependency checks and linked execution remain pending. The Swift consumer
`bash scripts/test-window-presentation.sh` for the 57 executable model assertions.

Five additional collection cases compile against the genuine native owner: all-original attachment before commit, second-member failure rollback with order/pin/opener/selection, durable-commit refusal, duplicate/foreign-source preflight, and nested single-transfer refusal. Both actual UnloadController reservations remain held across the collection. These cases have not been linked or executed; no browser test is claimed. The collection caller retains empty source and destination Browsers, including a destination created for a refused attempt, because either physical shell may still own local content. This differs deliberately from the single-page cleanup described above.
