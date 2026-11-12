# Settings control states and motion — SET25

Settings changes panes immediately and leaves sheet presentation to AppKit.
Reselecting the current pane does not repeat a transition or resize animation.
Preference changes do not acquire a generic spring, scale, sound or haptic.

## Profiles command rows

`SettingsHoverButton` owns one tracking area and immediate redraw without
replacing native button tracking, target/action, keyboard or accessibility.
Command and profile rows show no hover fill; they keep the pointing hand and
show a faint label-tinted fill with 8-point corners only while pressed.
Disabled controls use 0.25 opacity and no press fill. Layout/repaint disable
implicit layer animation. The real command dispatcher closes Settings only
after accepting an action; refusal retains its error presentation.

Hover requires an enabled visible control in the active key window, inside
both bounds/visibleRect and its actual native hit target. Covering views,
sheets, hiding, close, detachment and app/key loss retire it. Reentry uses the
current pointer. Former-window notifications cannot affect a replacement owner.
No delayed callback may write preferences or dispatch actions.

## Modal and ordinary controls

Native sheets, alerts, file panels and popovers retain original window/Profile/
controller ownership and AppKit's animations. Profile-removal buttons use
36-point height, 6-point corners and matching neutral/destructive palettes,
choosing pressed before hovered before idle. Disabled destructive actions stay
disabled in every state. Actual NSButton highlighting supplies press feedback;
there is no competing tracking area.

Checkboxes, switches, popups, toolbar selection and ordinary sliders retain
native state tracking. The haptic preference controls the sidebar drop-index
producer; the switch itself emits no haptic. Capture sounds and theme feedback
retain their own owners.

## Preserved specialized controls

The [icon picker](app-icon-picker.md) keeps its pressed radio indicator without
hover scaling. Shortcut rows/recorders retain their own opacity motion, native
editing and hidden/sheet/key-window suppression, including Reduce Motion.
The local [membership card](settings-membership-card.md) owns its own pointer
motion. Routing errors/scroll belong to [routing interaction](routing-interaction.md).
Default-browser requests retain actual asynchronous results; status refresh is
not success feedback. Quit confirmation belongs to application lifecycle.

## Checks

`scripts/test-settings-hover.sh` uses inert AppKit components to cover native
hit testing/actions, enabled state, covering views, window identity, sheets,
hiding and detachment. Only activation/visibility/pointer inputs are substituted;
no browser or real preferences are used.
