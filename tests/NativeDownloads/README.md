# Profile downloads and native file selection

`NativeDownloads` observes the actual Chromium Profile's DownloadManager and
DownloadItems, including restored history. Chrome Web Store CRX installs
(`IsExtensionDownload`, `application/x-chrome-extension`, `.crx` targets) stay
off this observer so they become Site Control Center tiles, matching Chrome's
download bubble. Updates contain copied values and the
manager's GUID, qualified by the exact persistent profile path. Closing the
originating page does not discard the transfer or its control identity. Pause,
resume and cancel resolve that GUID in that same live manager; acceptance of a
command is not reported as completion. DownloadItem remains the source of state,
bytes, failure reason, safety verdict and capabilities. Shell callbacks are
posted nonnestably after the item observer frame, even if a later observer
runs a nested loop; shutdown removes observers and invalidates
queued service callbacks.

The application no longer overrides target determination through
CefBeforeDownloadCallback. It retains ChromeDownloadTargetDeterminer, filename,
enterprise policy, safe-browsing and insecure-download decisions. A new profile
one-time pass per persistent Profile directory (`ClearSeededDownloadPrompt`)
clears it, keeping a stored false and any managed value. Native profile downloads without a CefBrowser
are no longer cancelled merely for that missing page. A prompt without a source
page now obtains a registered native window for that exact Profile, creating a
normal profile window if none is available. The real application installs the
parent-provider callbacks and cancels outstanding dialogs before unregistering
them on shutdown; the reusable dialog service has no reverse application dependency.
GUID, item identity, weak Profile and physical window are rechecked before accepting
a selection. Item/profile destruction, parent closure, profile selection changes
and competing security presentation cancel the one-shot dialog.

Ordinary security review is now connected to the Downloads window. The themed
sheet displays actual `DownloadBubbleSecurityViewInfo` warnings and allowed
Keep/Discard choices. A weak original Profile plus a per-incarnation item token,
GUID and copied warning/action state bind each decision; the engine rederives
those values before executing genuine `DownloadCommands`. Keep is never inferred
from `IsCommandEnabled` alone. Retry follows the real bubble controller's last-URL
request through the original Profile's DownloadManager because the pinned generic
RETRY command is a no-op. Target selection, policy and safety remain upstream.
Encrypted-archive password/deep-scan submission, enterprise REVIEW and help/settings
routes are the next implementation, not substituted with ordinary Keep.

`97df76204405d2046261e9f8efeb0cb84f74bf9c223b81f3567e6087b52967a8`
has context-owned downloads at `0x3dd4cc0`, a weak delegate setter at `0x68c6d8c`,
lifecycle callbacks at `0x68c743c–0x68c764c`, and real item controls at
maps copied item state to the UI. This supports context/item ownership; it does
sheet is an explicit current-engine adaptation pending the required polish pass.
Only source review was performed for this increment; historical checks below are
not new browser-test results or current P0 completion gates.

`NativeFileDialog` wraps the real macOS SelectFileDialog. It preserves type,
multiple selection, file extensions and selected filter, directory-selection
mode, caller URL, and policy. It binds the exact TabInterface, Browser and native
window before starting. Page detach, navigation, window closure, listener loss,
or a changed owner cancels rather than transferring the selection to another
page. A shared-window security reservation closes competing native extension UI.
The chooser must retain the sole exact reservation after acquisition and through
selection acceptance. A same-window competing lease cancels it; unrelated-window
leases do not. The wrapper keeps the platform runner locally alive through
terminal listener and reservation-release callbacks, then posts nonnestable
retirement after they return.
It routes the base class's asynchronous policy refusal through the same
exactly-once finish path. It does not replace Chromium's MIME/file-input handling
or implement a second file-picker model.

The Swift Library stores profile/GUID identity and actual terminal/error state.
Live controls are never persisted as if they were reusable callbacks. Reopened
history has no controls until the real profile manager republishes the item.
Dangerous/insecure items expose review-required state and cannot be resumed or
revealed through this UI; the separate review/accept/discard interface is still
missing, and this work must not bypass those decisions.

## Profile download settings

Settings reads and writes the actual persistent Chromium Profile's DownloadPrefs:
the folder uses SetDownloadPath (including SaveFilePath), and the prompt uses
kPromptForDownload. An immutable native snapshot carries weak Profile identity;
the application validates the current registered profile before and after each
write, retaining the real CEF request context across synchronous observers.
Stale, closing and private profiles cannot receive these writes. Managed values
remain authoritative. The Swift folder sheet cancels on Settings close or profile
change and rechecks its original owner before accepting a selection.

0x68ccb18/0x68ccb6c and downloadFilePath at 0x68ccbdc/0x68cccec, using BOOL and
NSURL file paths. The weak identity, effective snapshots and current Chromium

Three exact-owner native compiler checks and the complete Swift consumer
typecheck pass. Eight added TestingProfile/DownloadPrefs cases compile but have
not executed. Integrated build, actual folder/prompt changes, saved-file hashes,
same-profile restart, second-profile isolation and sheet cancellation still need
runtime checks. Original Settings appearance/motion remains separate.

## Evidence and adaptation

`97df76204405d2046261e9f8efeb0cb84f74bf9c223b81f3567e6087b52967a8`:
context manager `0x3dd4cc0`, initialization/create/update/remove callbacks
`0x68c743c..0x68c764c`, pause `0x68d0e20`, resume `0x68d0f88`, cancel
`0x68d0e78`. The native manager owns item state; its delegate is weak. The copied
filename completion block is `void (^)(NSString *)`; an empty result was not
proven to mean cancellation. Parc uses current Chromium156's real target and
SelectFileDialog callbacks instead of guessing the older callback's semantics.
The original save/open sheet layout and motion were not recovered in this batch.
The context-owned start path at `0x68c6fb8`, item association at `0x68d0a74` and
explicit cancellation at `0x68d0e78` support downloads outliving their source page.
parent-selection rule is not established. The real Chrome DownloadFilePicker,
target determination, caller authority and safety checks remain in the pipeline.
Per current user direction, unrun browser tests do not hold this source path open.

## Directory-upload confirmation correction

The v74 native run passed single/multiple uploads with server hash checks, then
aborted on directory confirmation at `NativeWidgetMac::InitModalType`. The real
`FileSelectHelper::OnListDone` requested a child Views dialog, but the supplied
app-owned NSWindow was not a NativeWidgetMac parent. Overlay81 corrects this
source boundary; the fresh v82 runtime results below verify the tested flows.

above, uses the real Views dialog model: `0x6958160` constructs it and the call
at `0x69587b4` reaches `0xa4cfea4` → `0xa33a36c` → the genuine modal host/window.
Fresh REA evidence is
`ev_f68237e83a38dd01fae5b2f42995e5f995f92f8a4f5663104f89c317b763d4ed`.
Parent lookup `0xeeb014–0xeeb1fb` requires `NativeWidgetMacNSWindow` and its
`bridgedNativeWidgetId` (evidence
`ev_6e881d3d6a9a1b4a8ab7668f797678bbe924cfd1f3ce333454c156e7cdfdd5df`).
auxiliary attachment factory and original confirmation appearance/motion remain
unresolved; this is not attributed to a Chromium142→156 requirement change.

Parc retains the actual `BubbleDialogModelHost`, Views controls, Cancel default,
input protection, enumerated files and original content-analysis/listener
continuation. Its scoped adapter attaches the genuine auxiliary dialog window
to the exact native owner; the real WebContentsModalDialogManager blocks page
input. Exact document/attachment/security checks cancel stale consent, including
an OK queued before deferred close. Only this route enables the acceptance
validator; ordinary dialogs retain their original action. Synchronous manager
close during registration removes the inserted entry, and manager continuation
checks lifetime/current queue after reentrant callbacks. No BrowserView or
replacement confirmation UI is created.

Eight private strict compiler checks pass using the actual generated owners'
flags. Ten genuine Browser/Widget/model cases compile, including Cancel/OK,
source loss, release-time competition and destruction, and cancellation before
and after modal registration. They have **not executed**; the ordinary Chrome
test-main/CEF initialization constraint remains. Generated object membership and production linking now pass. All seven
related target header checks pass after removing an unused test include; the
separate pinned CEF target still has ten existing include-visibility failures.
The v82 production package passes strict signing/provenance. Fresh runtime checks
pass genuine Cancel/Accept, both transferred file hashes, pending-confirmation
navigation cancellation and owning-tab closure. Physical parent-window close
remains unverified. Ordinary Quit with a pending confirmation reached Chromium's
teardown watchdog after page destruction; the dialog is not established as its
cause. These results do not complete P0-20 or its visual/motion parity.

## Verification

Run the executable Swift persistence/control tests:

```sh
bash tests/NativeDownloads/run-model.sh
bash scripts/test.sh
```

After the reviewed overlay is applied and its genuine targets generated:

```sh
python3 tests/NativeDownloads/check-chromium.py /absolute/chromium/src
```

The checker requires matching reviewed source/output hashes, actual object
membership and actual generated flags. It does not generate, link or execute.
`download_unit_tests` contains twelve real DownloadItemImpl/controller cases; only
the manager lookup/ownership boundary is a test double. Two regressions enter a
real nested loop from a later item observer and destroy the actual item from the
shell callback only after notification returns, covering updates and manager
shutdown separately.
`file_dialog_browser_tests` contains eleven genuine Browser/native chooser cases,
including actual sheet attachment, source loss, reentrant listener destruction
both orders of asynchronous policy refusal versus page detach, reentrant lease
acquisition, competing-window isolation, and native completion that spins a
nested loop while releasing its owner. A genuine auxiliary WebContents without
a TabInterface cancels once without a sheet or reservation; the constructor uses
the optional tab lookup rather than crashing on this legitimate non-tab caller.
This safe refusal does not provide docked DevTools with an auxiliary chooser owner.

Integrated model execution: 25 download-model assertions and all 420 BrowserStore
assertions pass. The combined Swift application typechecks. Isolated pinned
compiler checks use existing compatibility flags, not the future actual new
targets. The genuine Chromium tests have not been linked or executed.

Before acceptance: run the actual-target checker and linked tests; verify file
input/multiple upload/directory selection, save cancellation/overwrite/filter,
active pause/resume/retry/cancel, progress with no known total, background-tab
closure, two profiles, history reload, pending-download quit decisions and
shutdown. Check a real native Parc window rather than inferring it from ordinary
Chrome test windows. Browserless save prompts, dangerous-download review UI,
destination preferences UI, drag/drop and exact original Library/popover design
remain open. Full P0-20 and visual/motion parity are not claimed.

Version 37 registers the shared production/controller/browser-test targets and
removes the superseded independent-engine page-only download delivery. The
application preserves the already integrated relaunch, permissions and live-tab
transfer routes. Ten combined compiler checks pass with existing compatibility
settings; read-only replay validates 110 mapped files and 101 patched targets.
The full Swift consumer remains a typechecked candidate pending production
backend until the independent runtime is verified and promoted.
