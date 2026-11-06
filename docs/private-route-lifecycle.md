# Open Link in Incognito: shared private lifecycle handoff

ROUTE12 owns the original context-menu/navigation path and its native
implementation. WIN11 supplies this lifecycle contract for integration; the
reservation below is a required interface, not an assertion that it is already
implemented. Neither this handoff nor the current source establishes runtime
acceptance.

## Existing source boundaries

Chromium's `render_view_context_menu.cc` dispatches the actual link URL, source
frame URL and origin, `OFF_THE_RECORD` disposition, context-menu flag and
navigation-handle callback through `OpenURLWithExtraHeaders`. The pinned
`browser_navigator.cc` first applies its normal incognito URL policy, then
`OFF_THE_RECORD` asks the source Profile for its primary OTR Profile and finds
or creates a Browser. It also maps OFF_THE_RECORD to a foreground tab when the
source is already OTR. These are Chromium paths, not permission to replace the
request with a URL-only replay.

`PCNativeBrowserApplication.preparePrivateBrowsing(profilePath:completion:)`
loads/checks the exact normal parent but does not make an OTR Profile, Browser,
route or page. `AppDelegate.createPrivateWindow(parent:completion:)` retains
its request and revalidates that same parent/path after preparation. The native
`beginPrivateBrowsingWithProfilePath:error:` then obtains the parent's primary
OTR Profile, registers its exact `NativeRoute` if absent, initializes private
services, and supplies a `PreparedAppKitWindow` as the Browser reservation.
`NativeRoute` is Profile user data: `RegisterNativeRoute` expects no existing
entry, and `GetNativeRoute` must be called on the exact OTR Profile. A native
route is not inherited by the OTR Profile merely because its original Profile
has one. `PreparedNativeWindow.CanBind` and `Bind` consume the exact Profile,
window type and one-use native-window reservation. `NativePrivateProfileForWindow`
requires the original live registered binding, a live OTR Profile, no shutdown
or Profile-removal block and at least one Browser; it is not a factory.

The present new-private-window code records whether it created the primary OTR
and, on failure, asks `ProfileDestroyer::DestroyOTRProfileWhenAppropriate` when
that Profile has no Browsers. `PreparedAppKitWindow` tracks pending reservations
per binding, not per parent/OTR Profile. Thus an empty Browser collection alone
does not prove another reentrant or pending private-window request has released
its claim. ROUTE12 must not copy this local cleanup assumption into a second
creation path.

## Required shared interface and ownership

The two paths need one main-thread, original-Profile-scoped pending-creation
owner shared by normal private-window creation and ROUTE12. Its exact C++ API
name is an implementation choice; it must provide these operations:

1. Acquire an identity-bearing reservation **before** creating or initializing
   a primary OTR Profile or calling an operation that can reenter creation.
   Revalidate the exact original Profile, policy, removal/shutdown state, source
   window/frame/document and original request on every callback boundary.
   Reentry for a parent already being initialized must either join a safely
   retained pending operation or refuse before consuming the original request;
   it must never initialize/register a second context or overwrite another
   reservation. Any deferred continuation must retain the original request and
   complete/cancel its callback once, rather than reconstructing navigation.
2. Resolve the actual primary OTR Profile and ensure `GetNativeRoute(*otr)`
   returns the matching Profile's route, provider and lifecycle client before
   Chromium reaches `PrepareBrowserWindow`. Recheck after callback-capable work;
   `RegisterNativeRoute` is not an idempotent substitute for that recheck.
   Already registered, live OTR Browsers are an independent fast path and must
   keep their actual shared Profile and context, not create another OTR owner.
3. Give each new Browser its own `PreparedNativeWindow`, bound once to the exact
   OTR Profile/type/window. Hold the shared Profile-level reservation until the
   Browser has actually bound or creation has failed/cancelled. A per-window
   `pending_reservations` count does not replace this shared lifetime.
4. On failure, retire only the caller's window reservation and any Browser it
   actually created. Never destroy an OTR Profile that existed before the
   operation, has a Browser, is used by another pending reservation or has
   changed identity. If this operation created the Profile and it is still
   genuinely orphaned, defer cleanup until **all** Profile-level pending claims
   have resolved, then recheck exact weak identities and Browser/lifecycle state
   before Chromium's appropriate OTR destruction. Do not unregister shared
   route user data while another owner can use it. Preserve the original
   failure/abort ownership and avoid duplicate completion.

Keep the original `NavigateParams`, source frame/document and callback,
Chromium sanitization and policy, request context and destination disposition
through delivery. Never open a private URL in a normal Profile as fallback, and
never invent a private Profile or replay a URL to stand in for the original
request. Parent/Profile removal and shutdown cancel or refuse pending admission
without changing another request's outcome.

## Completion criteria

ROUTE12 should integrate the shared lifecycle owner into every path that can
create or register that primary OTR Profile, including the existing private
window factory, then demonstrate with deterministic inert/component checks:
existing registered OTR reuse; first OTR creation; synchronous reentry and
multiple pending requests for one parent; failed and cancelled creators in both
orders; another Browser appearing before cleanup; stale source/frame, parent,
Profile-removal and shutdown rejection; exact one-use window binding; and
single callback completion with the original request preserved. Verify source
and native syntax/applicable compiler checks under the current restrictions;
no functional browser tests are authorized. Any implementation detail that
cannot preserve the original request must remain explicitly unresolved, not
be counted as completed.

## ROUTE12 / WIN11 agreement

ROUTE12 owns implementation of the shared native lifecycle owner and its
integration with both the existing `beginPrivateBrowsingWithProfilePath:error:`
factory and Chromium's `OFF_THE_RECORD` navigator branch. WIN11 agrees to that
boundary and retains ownership of the private app/window behavior. This is an
agreed interface and completion contract; it is not yet implemented.

The concrete proposed C++ interface is a main-thread-only
`PrivateRouteReservation::Acquire(Profile& original)` returning an owning
one-use reservation or an explicit busy/unavailable result. Acquisition must
record a per-original-Profile pending claim before any reentrant OTR creation.
Its `Prepare()` resolves the exact primary OTR Profile, its registered
`NativeRoute`, and retained `CefRequestContext`; it returns those original
identities together, or refuses without consuming the original navigation.
Initialization already in progress for that parent is an explicit busy result
unless the implementation can safely retain and resume the original request.
`CommitBound(BrowserWindowInterface&)` succeeds only once for a Browser whose
Profile is that same OTR Profile and whose original native-window reservation
actually bound. Destruction/cancellation releases only that claim. The shared
owner, rather than one caller's local closure, decides whether a newly-created
OTR context is truly orphaned after the last claim resolves; it rechecks weak
parent/OTR identities, live Browsers, shutdown/removal and all pending claims
before asking Chromium to destroy it. A context that predated the cohort is
never destroyed as a failed creator's cleanup. Names may adapt to local C++
conventions, but the admission, identity and lifetime boundaries are required.

Existing live registered OTR Browsers continue through their exact current
Profile/route/context. A newly created OTR route must be registered before
`PrepareBrowserWindow` and rechecked after provider callbacks. The source
frame/document and original `NavigateParams`, sanitization, navigation-handle
callback and completion remain Chromium-owned throughout; provider reentry,
source destruction, policy changes, cancellation and shutdown each resolve
once without URL replay or substitution. Deterministic checks must cover the
interleavings in the completion criteria above, especially two pending claims
where the creator fails first and another claim or Browser survives.

On the current worktree audit, WIN11 has no active edits to
`native_appkit_application.mm` or `native_host_route`; WIN12's staged AppDelegate
restoration changes do not edit the private-window factory. A separate older
`downloads-accessory-delivery` worktree has unrelated dirty changes in
`native_appkit_application.mm`; its current ownership was not established by
this audit, so reconcile current main and other active owners before editing.

### Last-Browser destruction is a separate required boundary

Verified in the pinned `chrome/browser/ui/browser_manager_service.cc`:
`DeleteBrowser` snapshots whether the collection is empty, retains a weak
Profile, destroys the Browser entry, and then calls
`ProfileDestroyer::DestroyOTRProfileWhenAppropriate` for a surviving primary
OTR Profile with a regular parent. The Browser reset itself can release the last
CEF context and may synchronously shut down the Profile; the source explicitly
warns that the manager may be destroyed there. A counter consulted only by
Parc's failed-creator cleanup is therefore insufficient. The existing
`native-host-route.patch` already owns this Chromium file.

ROUTE12 and WIN11 agree that the same Profile-scoped lifecycle owner must also
interpose the last-Browser destruction decision. While any exact-parent/OTR
claim is pending, it retains the matching CEF context for the whole claim and
records the last-Browser destruction request instead of letting that path
schedule OTR destruction. Its guard must be established before callback-capable
Browser teardown and rechecked after it: reentry during reset may add a claim or
bind a new Browser. The final claim release evaluates the deferred request once,
using live weak identities and a fresh actual Browser/pending-claim check; if a
Browser appeared, it must not destroy its Profile. If genuinely empty and still
eligible, it delegates to Chromium's normal destruction path once. Ordinary
last-Browser teardown remains effective when no claims exist. A deferred natural
last-Browser destruction is distinct from failure cleanup: the latter must not
destroy a pre-existing context merely because a new creator failed.

A retained CEF context alone is not claimed to be a universal Profile keepalive.
Before implementation is accepted, inspect every relevant primary-OTR teardown
entry and establish that no independent path can destroy or schedule destruction
while the claim is live; preserve forced shutdown semantics and avoid touching a
manager or Profile after callbacks may destroy them. Test, without a browser,
last Browser removal while a second creation is pending; nested creation during
Browser reset; both pending-failure orders; final release with and without a
new Browser; exactly-once deferred teardown; and parent/shutdown invalidation.
Until those checks and the teardown audit are complete, this remains a required
contract, not a completed safety property.
