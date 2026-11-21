# Native responder coordination

Run `swift test --filter FocusManagerTests`. It compiles the Parc-owned focus manager and page host against AppKit with warnings treated as errors, then runs one test per behaviour. The tests create real, hidden NSWindows; they do not launch a browser or Chromium, show windows, read profiles, or use another browser's binary.

The component is a per-window responder registry, not a pane-cycle implementation. The shell supplies stable keys, retains each registration token, and provides any eligible pane ordering separately. `focusedKey` reflects the exact registered normalized actual responder: a page-host ancestor can preserve renderer focus without falsely reporting that the host itself received focus. Native text-field editors normalize to their containing NSTextField, preserving the selection during repeated requests.

`requestFocusForKey:` validates the current responder chain against the manager's actual NSWindow. It preserves existing descendant focus and suppresses repeated requests to the same pending responder for strictly less than two seconds. There is no timer or automatic delayed retry. `Accepted` means AppKit accepted the request; it does not certify that a deferred page renderer has focused. Actual firstResponder KVO drives resign/become callbacks. An optional `fallbackKey` is consulted only when the actual first responder is nil and no fresh pending request remains. Find dismissal must explicitly restore its previous key or the selected page key; setting the fallback does not dismiss or select anything.

Registrations and the window are weak. The pending value temporarily retains its target; unregistering, invalidating, or detecting detachment clears it. Callbacks should capture their owners weakly. The manager's API and lifetime belong to the main-thread window owner. Request/reconciliation delivery retains the manager through its lexical scope, so a resign or become callback may release the final external owner safely. Retained registration tokens can be invalidated explicitly; a final token release on another queue schedules generation-checked removal on the main queue. Window close invalidates the manager. Invalidation is terminal and does not close the page or change native focus.

## Lifetime safeguards

Generation-safe token removal, malformed-chain detection, explicit invalidation,
detached-pending cleanup and reentrant callback checks protect native owners.
The queued page-host callback retains weak original window/renderer identities
and requires the host to remain first responder without a sheet. A superseded
request cannot change a later native control or physical window.

## Coverage and ownership

The suite exercises actual native focus, automatic KVO ordering, external focus changes, real NSTextField editing and selection, descendant preservation, same-window validation, live page-host reparenting, weak ownership, registration replacement, teardown, reentrant callbacks, owner release during resign/become delivery, and deferred page-host focus through the real main run loop. Queued page focus is also superseded by a later native control, original host transfer, renderer replacement or invalidation; a new explicit request may focus the current renderer. A controlled NSWindow subclass injects refusal, acceptance without focus, and nil actual focus to test pending/fallback boundaries reproducibly; these injected states are not claims about normal AppKit behavior.

The shell supplies shortcut precedence, accessibility selection, hidden/modal eligibility and pane order through its real page/content identities. One responder should have one active key per manager; aliases have no specified callback-selection order.
