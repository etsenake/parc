# Private navigation creation lifecycle

Ordinary New Incognito Window and a routed private navigation must share the
same genuine primary off-the-record (OTR) Profile. A URL-only replay or fallback
to a normal Profile cannot preserve the original request's privacy and ownership.
This document retains the unresolved ROUTE12 creation-lifetime contract; it is
not a claim that the shared reservation below is implemented.

## Existing source boundaries

`preparePrivateBrowsing(profilePath:completion:)` loads/checks the original
normal parent without making an OTR Profile, route, Browser or page.
`AppDelegate.createPrivateWindow` rechecks that parent/path after preparation.
`beginPrivateBrowsingWithProfilePath:error:` obtains the primary OTR Profile,
registers its `NativeRoute`, initializes private services and supplies a one-use
`PreparedAppKitWindow` reservation. The route belongs to the exact OTR Profile;
it is not inherited from the normal parent.

Current failure cleanup records whether this attempt created the OTR Profile
and asks Chromium to destroy it when it has no Browsers. Window reservations
are per binding. An empty Browser collection alone does not prove that another
pending or reentrant creation released its Profile-level claim.

## Required shared interface and ownership

A main-thread owner shared by every OTR creation path must:

1. Acquire an identity-bearing original-Profile claim before callback-capable OTR
   creation/initialization. Reentry either joins a safely retained operation or
   refuses before consuming the original navigation; it cannot register twice.
2. Resolve the exact primary OTR Profile, route, provider and retained CEF context,
   rechecking after callbacks. Existing live registered OTR Browsers remain a
   reuse path, not a new context factory.
3. Give every new Browser a separate one-use window reservation bound to the exact
   Profile/type/window. Keep its Profile claim until actual binding or failure.
4. Release only the caller's reservation on failure. Destroy a newly created
   orphan only after all claims resolve and weak identities, Browser counts and
   shutdown/removal state still permit Chromium's normal teardown. A context
   predating the operation cannot be destroyed as failed-creator cleanup.

Preserve original `NavigateParams`, source frame/document, request context,
sanitization, disposition and navigation callback. Parent removal, source loss,
policy changes or shutdown must complete/refuse once without reconstructed
navigation or retargeting another request.

## Last-Browser destruction

The shared owner must also cover `BrowserManagerService` last-Browser teardown,
not only Parc's failed-creator closure. Destroying a Browser can release the last
CEF context, reenter creation or destroy the manager/Profile synchronously.
While an exact-parent/OTR claim exists, retain its matching context and defer
natural teardown. Recheck after callback-capable destruction; final claim release
may request normal destruction only if the exact context remains eligible and no
Browser appeared. Deferred natural teardown differs from failure cleanup.

A CEF context reference alone is not proof of a universal Profile keepalive.
Audit every primary-OTR destruction entry, preserve forced-shutdown semantics,
and never touch a manager/Profile after callbacks may have destroyed it.

## Completion checks

Inert/component coverage must exercise existing-context reuse, first creation,
synchronous reentry, two pending claims, failed/cancelled creators in both
orders, last-Browser destruction during a claim, a new Browser appearing before
cleanup, exact one-use window binding, parent/shutdown invalidation and
exactly-once callback/teardown. Source/compiler checks are separate from runtime
acceptance. The actionable integration remains in [the backlog](backlog.md).
