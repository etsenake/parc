# Settings control states and motion — SET25

Settings keeps native pane changes and native sheet presentation. It does not
apply a general spring, scale, haptic or sound to preference changes. Custom
controls use their own recovered state palettes, with the original action and
preference owners remaining authoritative.

## Reference and pane transition

`4e452201e483b5480c0403a9ef8566e10515cdcb78828622ff9032b202e29547`.
The recovered-components index, Swift type table, cross-reference index and
annotated-function helper resolved the following contracts without new
decompilation. This is recovered behavior, not original source.

`SettingsWindowController` supports an optional animated transition. Its
ease-in/ease-out `NSAnimationContext`, resize the window and crossfade child
controllers. Those constants are not ordinary Settings transition settings.

The ordinary path calls the native child-controller transition with options
window title. Parc therefore keeps an immediate pane swap, no window-size
animation, and no duplicate pane transition for a repeated selection. SET26
owns the corresponding native responder/recorder preservation.

## Profiles command rows

`NewManageView.DataActionButton` stores `hovered`, `isEnabled`, `colorScheme`,

  no hover background.
- The complete control uses opacity 1 when enabled and 0.25 when disabled
  ordinary text resolves black/white from the original color scheme.
  is no stored pressed value, custom button style, animation, scale or haptic
  in this body or hover setter. A generic pressed palette would change it.

SET24 owns `SettingsCommandButton`'s static composition and palette. SET21 owns
its genuine command callbacks and accepted/refused result. SET25 supplies the
native `SettingsHoverButton` base: one tracking area, immediate redraw and no
changes to native NSButton target/action, press tracking, keyboard or AX action.
The published command-row consumer disables implicit Core Animation actions
when laying out or repainting its hover layer. The six genuine Profile commands
still close Settings only after their original dispatcher accepts the action;
refusal leaves the original error presentation in place.
The AppKit adaptation admits hover only for the visible, enabled, active key
window control, within both its bounds/visible rectangle and its actual native
hit target. Overlay views, sheets, close, window replacement, hiding and app/key
loss retire that hover. Reentry and re-enabling use the actual current pointer;
old-window notifications cannot affect a new owner. No delayed callback can
write a preference or dispatch an action. These lifetime guards are an explicit

## Modal and ordinary controls

The existing Settings owners retain native `beginSheet`/`endSheet`, `NSAlert`,
save/open panels and popover presentation. Dismissal and accepted-action callbacks
stay with their original window/Profile/controller. SET26 owns original-responder
capture/restoration and interruption; SET23 owns removal-sheet presentation and
recovery. Closing or cancelling does not create a new success animation or
feedback event. AppKit owns native sheet animation and system Reduce Motion;
there is no additional Parc modal animator or timer to cancel.

vertical padding 10, height 36, continuous radius 6, shadow radius 2 and border
`NeutralButtonPressed/Hovered/Face` for neutral/cancel controls and
`DestructiveButtonPressed/Hovered/Face` for enabled destructive actions. Disabled
destructive actions retain their disabled color across all three branches.
Foreground, border and shadow use the matching named family
updates state directly; no scale, spring or haptic is introduced. SET23 applies
this contract to the removal controls while keeping their real acceptance and
cancellation gates. `ProfileRemovalButton` uses the shared hover owner and
reads NSButton's real highlighted state for the recovered pressed palette. It
has no second tracking area or hover state to survive a sheet/window change.

Native toolbar selection, checkboxes, switches, popups, ordinary rounded
buttons and sliders keep AppKit state tracking. The Advanced haptic preference
continues to control the actual sidebar drop-index producer described in
[interface feedback](settings.md#interface-sound-and-reordering-feedback); the
preference switch itself is not a haptic producer. Capture sound and completed
Space-theme feedback retain their existing separate owners.

## Preserved specialized controls

The [Icon picker](app-icon-picker.md) explicitly disables RadioGroupButton hover
scale/border and preferred-heart feedback. Its accepted selection and pressed
radio indicator remain unchanged. The [Shortcuts composition](settings.md#shortcuts-settings-composition)
retains its particular opacity spring, native row/recorder states and existing
hidden/sheet/key-window suppression. The recorder's original animation already
honors Reduce Motion. Neither surface acquires the Profiles hover state or a
generic Settings animation.

The unrelated `AccentPreferencesButtonStyle` is not a reason to restyle every
Settings button. Its cross-reference consumers include excluded gifting and
remain excluded.

The existing General, Profile and Advanced inventory introduces no other custom
control-state or transition owner. Preview and Links use their existing native
sheet presentations; routing-editor-specific feedback remains in the separate
Routing family. Default-browser requests keep their actual asynchronous
operation owner, truthful result text and native button. A status
refresh does not synthesize accepted feedback. The application quit-confirmation
sheet belongs to the application lifecycle, not a Settings pane transition.
The explicitly added local membership card owns its pointer motion and local
controls under SET27; it is not governed by the command-row hover palette.

## Checks and completion boundary

`scripts/test-settings-hover.sh` compiles the actual production base into an
inert AppKit executable. It checks native action admission, real native hit
testing, disabled/re-enabled state, covering views, original/new window identity,
app/key loss, sheet admission/attachment/completion, hiding, close and detach.
Only OS activation/visibility flags and pointer position are substituted; it
does not open a visible window, post system input, start a browser or save data.
Compiler/component receipts are retained outside Git. They do not establish
hardware haptic feel, whole-Settings runtime or whole-product visual acceptance.

The production base passes 28 inert native assertions and the finished
whole-module SIL check with zero diagnostics. Fresh independent review found
and cleared the stale former-window/tracking-area event boundary before
publication `12e13ac1`. Its exact source remains unchanged in the integrated
tree. The command-row consumer (`c5824901`), removal-sheet hover integration
(`52a2be48`) and same-pane/native sheet lifetime integration (`b036bb9b`) each
received their own focused component checks, final whole-module SIL and fresh
independent clearance. SET25 reconciled those exact published sources and
verified the unchanged base, native press ownership, accepted-action gates,
same-pane early return and close/cancel lifetime paths.

SET25 is complete under the current source/component rule. Receipts and source
hashes are retained in `work/settings-coordination/set25`, with corresponding
consumer receipts in `settings-set24-evidence`, `settings-coordination/set23`
and `settings-coordination/set26`. Final closure changes documentation only;
the already-checked and independently reviewed implementation is unchanged.
SET27's newly included card and the later whole-product visual/hardware polish
retain their separate requirements. No functional browser tests ran.
