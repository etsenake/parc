# Profile downloads and native file selection

`Engine/ParcNative/downloads.cc` observes the actual Profile DownloadManager and
items, including restored history. Extension CRX installs use extension UI rather
than duplicate download rows. Copied updates carry GUID plus persistent-profile
identity. Closing the source page does not discard a transfer or its controls.

## Ownership and security

Pause/resume/cancel resolve the GUID in the original live manager. A command being
accepted is not completion; the item supplies state, bytes, errors and safety.
Notifications are posted nonnestably after item observers return, and shutdown
invalidates queued callbacks before releasing the manager.

Chromium owns target determination, filenames, enterprise rules and safety
checks. New profiles default to no save-location prompt. A one-time migration
clears the old seeded true value without overriding managed policy or stored
false. Browserless downloads obtain a registered native window for the exact
Profile, creating a normal profile window if required. Acceptance rechecks item,
profile and physical window; owner loss or competing security UI cancels.

Security review uses genuine DownloadBubbleSecurityViewInfo and DownloadCommands.
It binds a weak Profile, item-incarnation token, GUID and current action state,
and rederives them before dispatch. Keep is never inferred from enablement alone.
The implementation includes encrypted-archive passwords, deep scanning, enterprise
review and help/settings routes. Retry uses the real last-URL download request.
See [Downloads](../../docs/download-library.md) for current UI behavior.

## Profile download settings

Settings reads/writes the real DownloadPrefs folder and prompt values. Immutable
snapshots carry weak Profile identity; writes validate registration before and
after synchronous callbacks. Closing/private/stale profiles refuse writes and
managed values remain authoritative. A folder chooser cancels on Settings close
or profile change and rechecks its original owner before accepting.

## Native file chooser

Parc installs a `ui::SelectFileDialog` factory at startup, so every chooser
Chrome opens after FileSelectHelper and its SelectFilePolicy reaches
NativeFileDialog for the page the policy names, or for the page hosting an
inner page. A chooser that names no page is refused rather than parented to the
frontmost window. Profile-owned downloads without a page use their own
shell-selected parent.

NativeFileDialog wraps macOS SelectFileDialog with its real type, multiple-file
selection, filters, directory mode, caller URL and policy. It binds exact tab,
Browser and native window; navigation/detach/closure/listener loss cancels.
A shared-window security reservation closes competing UI. Only the exact sole
reservation can accept; unrelated windows are isolated.

The platform runner stays alive through terminal listener/release callbacks,
then retires nonnestably. Policy refusal and user cancellation share a once-only
finish path. Docked DevTools uses its registered auxiliary-page lease to bind
the chooser to the inspected tab and original native window. Detach, rebinding
or owner loss revokes the chooser; an unbound auxiliary page cancels without
falling back to another window. Print Preview names its preview as the source,
so Save to PDF binds to the preview's own window and its original document.

## Directory-upload confirmation correction

The real BubbleDialogModelHost and Views controls retain Cancel default, input
protection, enumerated files and content-analysis continuation. The adapter
attaches the genuine auxiliary window to its exact native parent while
WebContentsModalDialogManager blocks page input. Stale document, attachment or
security state cancels queued acceptance. Callback reentry checks the live model
and current modal queue before continuation. No BrowserView is fabricated.

## Verification

Model checks:

```sh
bash tests/NativeDownloads/run-model.sh
```

With the current reviewed overlay applied and genuine targets generated:

```sh
python3 tests/NativeDownloads/check-chromium.py /absolute/chromium/src
```

The compiler checker verifies source/output hashes and exact generated object
membership/flags. It does not generate, link or execute Chromium tests.
`download_unit_tests` uses real DownloadItemImpl/controller paths, including
notification reentry and shutdown. `file_dialog_browser_tests` covers actual
chooser ownership, cancellation, policy refusal, competing leases, nested loops
and owner destruction. Directory-confirmation cases use genuine Browser/Widget
models. `tests/NativeDevTools/auxiliary_browsertest.mm` covers actual auxiliary
chooser cancellation and refusal after detach. Treat compiled and executed
results separately.

Current rules prohibit browser/app launch; see [AGENTS.md](../../AGENTS.md) before
selecting any fixture.
