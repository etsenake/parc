# Extension interaction — EXT13

The shell keeps the real profile/browser/page action leases. An extension ID
selects presentation; it never authorizes a replacement extension instance.
Extension installation, native commands, permission dispatch and background
services remain the completed P0-13–16 owners. EXT11 owns installation and
discovery, EXT12 static surfaces, and EXT14 popup/panel lifetime and motion.

## Reference and comparison

`4e452201e483b5480c0403a9ef8566e10515cdcb78828622ff9032b202e29547`)
is the reference for this row. Retained contracts and the local component,
Swift-type, cross-reference and annotated-function helpers answered the
questions below; no additional REA/decompilation session was needed. Older
already-implemented ownership boundary, not new 1.122 UI constants.

- **Pinned sidebar actions.** `CommandBarPlaceholderButtonsView` factory
  This resolves the earlier unknown concrete class in the sidebar document.
  EXT12 supplies its 28-point surface, radius 9 and 16-point icon. Its shared
  ratio 0.6 and response 0.3, restarting from the presentation transform.
  separate SwiftUI producer: GrayA4 while hovered, clear otherwise, with no
  press style or animation modifier in that body. Its EXT12 surface is
  32 by 24, radius 6, with the same genuine 16-point icon. Parc's shared
  native action class takes an explicit style so the sidebar spring and
  pressed fill do not leak into the top bar. The actual overlay is
  constructs `_ControlButton`; it owns click, mouse-down, right-click and
  both SidebarCellButton and the Site Control Center entry button.
- **Site Control Center.** The retained [WEB14](web-interactions.md#site-control-center--web14)
  and WEB19 contracts resolve the secondary-button press/hover treatment,
  2-point picker ring, pin badge and 0.36-second hover-in delay with
  easeInOut(0.12). These remain in their original SwiftUI owners. The ring
  is decorative and cannot intercept pointer input or become an AX child.
- **Held-Command picker.** `SiteControlCenterViewController` installs one
  Read-only constants are left 123, up 126, right 124, down 125, E 14,
  focused item either chooses the first. Command release and Return select
  change while Command remains held cancels and passes through.
  Keypad Enter is an unrelated key. These findings replace WEB14's former
  character-E/keypad-Enter and inferred-wrap adaptations.
- **Disabled and menu behavior.** The real engine action supplies tooltip,
  accessible name and already-decorated icon. Its disabled action can open
  the genuine context menu, so the shell must not disable the entire action
  solely from `PCNativeExtensionAction.isEnabled`. Pin policy remains the
  actual `canChangePin`. The engine builds and runs each context menu on the
  real model; Parc only draws it (its themed menu beside the button, at Josh's
  request, see [WEB14](web-interactions.md#site-control-center--web14)), and
  no shell menu recreates permissions or command state.
- **Native content focus.** Real extension popup/side-panel contents retain
  their existing `ExtensionViewHost` and original native window. The popup
  shows its actual page and native key window, then focuses that host; the
  side panel's coordinator owns host focus. Existing native registry routing,
  renderer keys and context-menu keys are unchanged. EXT14 owns suspension,
  close, replacement and safe saved-focus restoration; there is no second
  shell shortcut dispatcher into extension web content.

## Parc ownership and accessibility adaptations

The picker monitor now belongs to the exact original anchor window and its
popover content window, including the pending address-pill show. An unrelated
window, sheet, moved anchor or inactive application cannot select an extension
or consume its keys. Windowless flagsChanged events use the already-validated
key window. A repeated begin advances the existing gesture; it cannot install
another monitor. Deactivation and detachment clear picker state, and close and
deallocation remove monitors. The selection callback captures immutable action
leases when the gesture begins, so a same-ID unload/reinstall cannot retarget
Command release. Original page/profile/security validation remains in the
existing callback and native action bridge.

These exact-owner guards and settled Reduce Motion behavior are Parc safety
monitor does not show the same native-window filters in the bounded body.

Pinned actions remain ordinary native keyboard stops in the existing window
key-view loop. Their explicit rounded focus mask now covers the correct
full Tab traversal. A hidden, detached or invalid action cannot dispatch an
AX press/menu or advertise itself enabled. Mouse-down retains its original
lease through AppKit tracking; hide, detach and key-window loss cancel its
pending press and visual state. Genuine blocked-action menus remain usable.

AX uses the engine's actual action name and Show Menu operation. In the Site
Control Center, a policy-allowed Pin/Unpin custom action reaches the same real
callback even when the visual badge is hidden before hover. The alternate-click
NSView exposes no duplicate AX element. These additional AX operations are

## Checks and limits

Only compiler and inert native/model components are used. The extension
control component passes 38 assertions and the integrated Site Control Center passes 61.
The whole-module typecheck and final SIL pass with warnings as errors and no
diagnostics. Independent review corrected the native press hook to receive
AppKit's actual NSButtonCell highlight transition; the inert component checks
that transition for both press/release and the distinct top-bar behavior. An
inert EXT12 appearance specimen also caught AppKit restoring image-overlap mode
when the icon changes; each update now restores image-only mode, with tests for
both real and fallback artwork while keeping the accessible title.
The extension control component checks original action/menu callbacks, invalidation,
hide/detach rejection, labels, focus-mask bounds, ordering and compression.
The Site Control Center component checks physical picker keys and wrap/empty
selection plus the existing model/layout/close recipes. They never load a
browser or extension, send browser input, traverse a live AX tree, modify
preferences or claim functional keyboard/VoiceOver acceptance.

Local receipts and source-bound helper output are retained under
`work/extensions-checks/ext13`; EXT12 geometry reference output is under
`work/extensions-checks/ext12/evidence`. Runtime Tab order, live native popup
focus and VoiceOver acceptance remain unrun under the current instruction.
The implementation and static comparison do not claim those observations.
