# Native extension command registry

`Engine/ParcNative/extension_keybinding_registry.{h,cc}` implements the native
registration and dispatch boundary against pinned Chromium 157.0.8103.80. It
uses the actual owning Browser's Profile and TabListInterface and derives from
Chromium's shared ExtensionKeybindingRegistry. It does not introduce a
FocusManager, a substitute Browser, a second event router or a second permission
grant implementation.

## Dispatch model

The window owns the registry; Chromium's base owns extension/command identities,
load/unload and edit observations, listener checks, permission-filtered tab data,
activeTab grants and user-gesture marking. Construction calls `Init()` to include
already-enabled extensions. Active regular named commands come from the real
`CommandService`.

Action accelerators run before named commands. Native event conversion preserves
virtual key, translated modifiers, key phase and timestamp. The native menu gets
its existing opportunity before the DevTools-to-window fallback; do not dispatch
extensions again from an earlier menu callback.

## Integration contract

Construct `parc::NativeExtensionKeybindingRegistry(browser, action_dispatcher)`
after the actual TabListInterface and extension services exist. The callback is
mandatory and must consult the owning browser's real action controllers. It
returns true only if an action handled the accelerator. It may destroy the
registry synchronously; a retained callback and weak-self check prevent fallback
into the destroyed object. An always-false callback is used only by tests that
isolate named dispatch; it is not an acceptable completed action integration.

The BrowserWindow owns the registry and destroys it before its Browser, Profile
and TabListInterface. Calls occur on Chromium's UI thread. Its post-renderer
`HandleKeyboardEvent` now calls `DispatchKeyboardEvent` only while selected in
the actual key window and outside teardown. IME events marked
`skip_if_unhandled` return false before either action or named dispatch.
`SetShortcutHandlingSuspended` blocks both action and named dispatch. Call
`OnHostActivationChanged` for initial registration, key/resign events and selected
browser changes within a shared NSWindow. Deactivation and destruction clear the
profile's active registry only if it still points to this instance.

The reviewed source overlay compiles this service in //parc:browser with a direct
dependency on Chromium's accelerator helper. The native client supplies its
menu-only `OnKeyEvent` route before Chromium's existing DevTools-to-Window
fallback. It must not also dispatch extensions. The typed native outer delegate
must retain the skip guard for direct calls; ordinary renderer ACK already
filters those events. Action controllers, popup services and the native BrowserWindow factory are
installed by the production host.
OS-global listener registration remains Chromium's responsibility.

## Checks

The seven real Chromium browser-test cases in
`extension_keybinding_registry_browsertest.cc` exercise:

1. An installed Manifest V3 worker receiving a command, with the owning Browser's
   current tab, activeTab grant, user gesture and actual event context.
2. Extension load, key reassignment, key-up rejection, action exclusion and unload.
3. Action-before-regular dispatch and shortcut suspension across both routes.
4. Conditional active-registry clearing across two Browsers and a second real
   Profile; commands from the first Profile must not dispatch in the second.
5. Synchronous registry destruction by an action callback, both handled and
   unhandled, without named-command fallback or stale global registration.
6. Native keyboard events preserve the registered virtual key despite differing
   text, and do not deliver commands for IME skip or mismatched key-up events.
7. Native action delivery preserves modifiers, repeat, phase and timestamp,
   with both IME skip and shortcut suspension preventing callbacks.

The test source uses the real Browser and EventRouter. It is not mapped into
the overlay's browser-test target; the production registry is mapped and connected to native dispatch.
