# Native site permission checks

`bash tests/NativeSitePermissions/run.sh` exercises the production AppKit
presenter, its transient popover and the main run loop. Inspect the runner and
follow [the working contract](../../AGENTS.md) before running window-based checks.

`permission_prompt_unittest.mm` exercises the production typed permission
prompt with real Browser/Profile/Tab/WebContents, PermissionRequestManager and
a native window. The notification case uses PermissionController and
HostContentSettingsMap. Cases cover Allow, accuracy selection, grouped
camera/microphone requests, Not Now, navigation, hiding, replacement,
exact host-detach cancellation and competing reservations during release.
The registered Chromium filter is `NativeSitePermissionTest.*`.

## Production ownership

Parc replaces Chrome's prompt factory at startup. It returns the manager-owned
prompt for auxiliary pages and for native pages that installed the service, and
binds the page's detach cancellation to that exact prompt. Any other page gets
no prompt: nothing is granted, and Chrome leaves the request pending or ignores
it. Each
request retains requesting/embedding origins, requesting documents, primary
document, Profile, Browser, native window and actual page view. Navigation,
hiding, detachment or closure cancel stale UI. Release may reenter, so the
adapter revalidates before delivering a decision.

Grants use the real `Accept` or eligible `AcceptThisTime` operations. Stop
allowing, Not Now and interruption become `Deny`, `Dismiss` and `Ignore`.
Chromium owns settings, temporary-grant lifetime and downstream device policy.
Geolocation uses Chromium's approximate, precise and upgrade choices.
Quiet requests stay suppressed.

Permission-element follow-ups are implemented for administrator decisions,
previous grants/denials, macOS permission requests and System Settings.
The adapter observes the actual flow stage, retains the original request while
macOS responds and advances the engine flow after refreshing system policy.
Prompt geometry metrics remain absent because this is an AppKit presentation;
the actual popover anchor is supplied separately by the native page host.

Screen/window/tab selection uses the registered `WrapNativeCapturePicker` route
and the genuine Chromium/system picker under its original document and security
reservation. Site setting changes and revocation use the Site Control Center's
real PageInfo presenter, including `OnSitePermissionChanged` and `OnUIClosing`.
These are separate connected owners, not missing permission-prompt screens.
See [web interactions](../../docs/web-interactions.md#dialogs-authentication-certificates-and-permissions--web15).
