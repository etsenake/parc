# Native extension command registry

`Engine/ParcNative/extension_keybinding_registry.{h,cc}` implements the native
registration and dispatch boundary against pinned Chromium 156.0.8078.48. It
uses the actual owning Browser's Profile and TabListInterface and derives from
Chromium's shared ExtensionKeybindingRegistry. It does not introduce a
FocusManager, a substitute Browser, a second event router or a second permission
grant implementation.

## Reference and adaptations

`97df76204405d2046261e9f8efeb0cb84f74bf9c223b81f3567e6087b52967a8`.
The retained report is `outputs/parc/arc-extension-keyboard-contract.md` in the
analysis workspace. Its original instruction addresses are:

- Native window-owned registry construction: `0x315e738`, base `0x2999e00`.
- Action-before-named-command dispatch: `0x68a4f4c`; REA evidence
  `ev_826904e7d769993af96afa0c44bf6c30a6bc048d1787c5e154684c198ed66464`.
- Native registration/removal: `0x68a51dc` / `0x68a537c`; registration evidence
  `ev_1d60662beb8cbebf216cde5361612ccc77b1398f861426c17f062c7bde0a1b65`.
- Shared command dispatch and active-tab resolution: `0x5e99ca8` / `0x68aab58`;
  evidence `ev_a665f041888d16218f16b0fa70acd31a5d04d56d30910d4f88abd84d96b2159d`.
- Set/conditionally clear the active profile registry: `0x68a5f5c` / `0x68a600c`.

The follow-up `arc-page-platform-contract.md` resolves the original fallback:
menu helper `0x6868c60` reaches the cached Browser delegate through its `+0xe8`
slot, adjustor `0xa504c94` and body `0xa504c3c`. That body tries DevTools, then
tail-calls the actual Window's registry. It contains no second menu attempt.
Fresh REA evidence for that Browser body is
`ev_11c52d03797a6b19228c6bacc639add5a8fa0a21b5ff0d9210a9c59d456320b9`;
the original branch instruction corroborates the decompiler's external tail.
Modifier helper `0x4751eb0` matches the shared Chromium conversion. Current156
`ui::GetAcceleratorFromNativeWebKeyboardEvent` preserves the same virtual key,
translated modifiers, key-up phase and timestamp without private-layout copies.

Chromium's base still owns the authoritative extension-ID/command-name targets.
This avoids redundant identity storage and preserves current Chromium's
accelerator matching and media-key behavior. The real base provides extension
load/unload and command-edit observation, listener checks, permission-filtered
tab data, activeTab grants before delivery, and user-gesture marking.

Two deliberate differences are explicit. First, construction calls upstream
constructor does not prove where its equivalent initial enumeration occurs.
Second, Parc returns `CommandService::GetNamedCommands(ACTIVE, REGULAR)` directly.
returns true for a nonempty map and the base only registers on true. Two agents
checked that bounded branch anomaly. Parc intentionally corrects it rather than
copying a route that appears to discard active named commands. This does not
remain unresolved.

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

The reviewed source overlay compiles this service in libcef_static with a direct
dependency on Chromium's accelerator helper. The native client still needs its
menu-only `OnKeyEvent` route before Chromium's existing DevTools-to-Window
fallback. It must not also dispatch extensions. The typed native outer delegate
must retain the skip guard for direct calls; ordinary renderer ACK already
filters those events. Action controller/popup implementation and production
BrowserWindow factory selection remain unfinished.
OS-global listener registration remains Chromium's responsibility. Native menu
precedence, renderer-consumed keys, repeat/layout/IME, media keys, worker restart,
incognito routing and real action popup ownership still require integration and
runtime verification. General Google networking is outside this task.

## Checks and current result

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

They are intended to link into Chromium `browser_tests` with the production
registry source. No dummy headers, fake Browser or replacement EventRouter is
used. Tests are not yet mapped into the reviewed source overlay.

Run the read-only syntax check once generated prerequisites exist:

```sh
python3 -B tests/NativeExtensionCommands/check-chromium.py /absolute/path/to/chromium/src
```

It reads actual `libcef_static.ninja` and `browser_tests.ninja` compiler flags,
uses the pinned Clang with `-fsyntax-only`, and writes logs only under ignored
`build/tests/native-extension-commands/`. It neither generates nor builds the
external tree. With the actual upstream generated prerequisites present, both
the production registry and all seven browser-test cases pass syntax-only
compilation using the pinned compiler and target flags, including warnings as
errors. This verifies source/API compatibility, not test execution: linked
browser tests and end-to-end shortcut UX have not run.
