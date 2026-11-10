# Live tab transfer checks

`NativeTabTransferTest.*` exercises the production `TransferLiveTab` function with actual Chromium Browser, TabStripModel, TabInterface, WebContents and UnloadController instances. Its twenty-two cases cover identical tab/page pointers, empty and nonempty destination selection, ordinary popup owners, cross-profile and unsupported owner refusal, last-source rollback, original pin/group/opener restoration on rollback, untouched and rolled-back preexisting-empty-owner preservation, explicit close ordering, owner-refill checks, failed source reattachment, callback-driven ownership changes, real close reservations, nested transfer and independent page destruction. The presentation callback stands in only for AppKit attachment; it does not implement tab ownership or close logic.

The shared `tab_transfer` source set is consumed by both //parc:browser and the test-only target, avoiding a //parc:browser dependency from chrome/test:unit_tests. Run `unit_tests --gtest_filter='NativeTabTransferTest.*'`. The overlay maps the production source set and the test target into the pinned engine.

## Native shell contract

`PCNativeBrowserWindow.transferPage(_:profilePath:container:completion:)` moves the exact page to the destination's actual Profile Browser. When absent, it constructs an empty native Browser through the real typed factory; it never creates a blank/replacement WebContents. Source and destination must be different physical registered windows with the same actual Profile. Normal and ordinary popup Browsers are supported. DevTools, document-PiP and app-specific owners use their separate ownership paths and are not transferable by this ordinary-tab API.

Before calling, reserve both shell ownership claims and attach a temporary plain NSView to the destination NSWindow. Keep the original PCBrowserView and its single PCNativePage observer alive. Pass the temporary view as the native transfer container. On genuine Transferred completion, move that same PCBrowserView to the destination, install the new owner/model claim and use the normal pageDidAttach path for its final container. Do not create a second adopting wrapper, call closeBrowser, navigate a URL, or let queued reconciliation adopt the same page again. Selection of a nonempty destination remains a separate explicit shell action.

Refused leaves the source unchanged. Restored means the actual tab was put back in its surviving source after attachment failed; the shell retains the source claim. Interrupted reports independent external page/owner mutation, requiring exact-identity reconciliation, never saved-URL reconstruction. Such independent destruction cannot be rolled back. Completion is posted, with native window/app close and another transfer blocked through result callback delivery. Ordinary native page close is blocked during the synchronous ownership change.

The current Chromium adaptation briefly reserves both real UnloadControllers. This prevents last-tab detachment from advancing empty-source close state before insertion or rollback. It releases on stack unwind and returns an optional weak-source close operation. The native caller runs it only after the posted Swift result callback has reconciled or retained its ownership claims and returned. The close operation rechecks actual emptiness and scheduled deletion. Preexisting destinations remain owned on every rollback, even if they briefly contained the moved tab; only an empty destination created by this native request is independently retired after the callback. This fixes ownership ordering, not a claimed rejection by a global busy flag: NativeBrowserWindow::Close itself enters the real UnloadController. The TestBrowserWindow fixture records the initial Browser::TabStripEmpty notification directly, so ordering tests observe the separately returned close operation after that notification, rather than pretending that fixture implements the native window's close gate. The hold accounts for Chromium's synchronous Browser::TabStripEmpty behavior.

The connected Swift consumer reserves both physical-window claims and keeps the original wrapper/observer. It uses the callback-free `PCNativeBrowserApplication.owner(of:)` lookup (actual TabInterface membership plus native Browser association), then requires successful final attachment before updating the claim. An interrupted third/unknown owner or failed final attachment stays reserved with its temporary container mapping; ordinary rendering, navigation and model retirement remain blocked until exact reconciliation or actual page closure. Retry/Close Page is a Parc recovery adaptation, with a separate presentation contract.

## Collection transfer and checks

Chromium owns delegate transitions through its actual tab-strip callbacks;
rollback restores surviving source pin/group/opener state. The overlay connects
the native bridge and shared controller/test targets. Shell ownership and
presentation checks run with `bash scripts/test-window-presentation.sh`.

Five collection cases cover all-original attachment before commit, second-member
failure rollback with order/pin/opener/selection, durable-commit refusal,
duplicate/foreign-source preflight and nested single-transfer refusal. Both
UnloadController reservations remain held across the collection. The collection
caller retains empty source and destination Browsers, including a destination
created for a refused attempt, because either shell can still own local content.
This differs from the single-page cleanup described above.
