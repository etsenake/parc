# Native site permission checks


`permission_prompt_unittest.mm` is the engine-connected suite for the shared production typed permission prompt. Its fixture uses real Browser/Profile/Tab/WebContents, PermissionRequestManager and an actual native window. It observes genuine manager decisions; the notification case invokes the actual PermissionController and HostContentSettingsMap, not a simulated grant. Request outcomes remain owned by the fixture through teardown. Cases cover Allow, the engine's accuracy selection, camera/microphone grouping, Not Now dismissal, hidden/window teardown, navigation, request replacement and exact weak host-detach cancellation, competing reservations and release-observer reentry. Current status: all 14 cases pass the pinned-flag syntax check; not yet linked or executed.


## Ownership and reference

The production adapter is shared with genuine-controller tests through `native_permissions`; the AppKit-only presenter is in `native_components`. The CEF platform delegate factory returns the actual manager-owned typed prompt only for Parc's native pages. Other CEF delegates retain their existing path. Camera and microphone use the normal Chromium media-policy/device/OS pipeline. Grants are genuine `Accept` operations (`AcceptThisTime` remains for a permission-element stage); Stop allowing, Not Now and interruption become `Deny` / `Dismiss` / `Ignore`. Chromium owns settings and temporary-grant lifetime.

Each request binds the canonical requesting and embedding origins, all requesting frame documents, primary document, Profile, Browser, exact native window and actual page view. The manager must still own that prompt at completion. Navigation, hiding, native detachment and closure cancel stale UI. The platform retains a weak cancellation callback for that exact prompt, so a delayed detach cannot cancel a replacement. Releasing the shared security reservation may reenter; the adapter revalidates before delivering a decision. While holding its lease it must be the sole owner, and any attached sheet must be its own. After release it rejects any replacement reservation or sheet. The genuine notification-controller regression verifies that a replacement acquired during release cannot persist an Allow decision. Shown-state acknowledgment follows actual visible attachment.



After the linked engine is available, run the registered `NativeSitePermissionTest.*` cases from `chrome/test:unit_tests`, then exercise real HTTPS requests, persistence/revocation, temporary expiry, OS authorization/device failures, split/multiwindow moves and complete native bridge routing. Target registration and compiler checks do not establish linked execution.
