# Extension interaction — EXT13

The shell retains real profile/browser/page action leases. An extension ID
selects presentation; it never authorizes a replacement extension instance.
Installation, commands, permissions and services stay with Chromium's owners.
See [extensions](extensions.md) and [lifecycle](extensions-lifecycle.md).

## Controls

Pinned sidebar actions use a 28-point surface, 9-point corners and 16-point icon,
GrayA4 hover and GrayA5 press. Press scales to 0.95 with response 0.3/damping 0.6
from the current presentation transform. Top-bar actions use 32 × 24 points and
6-point corners, with hover fill but no sidebar press spring. The actual engine
supplies decorated artwork, tooltip and accessible name.

A disabled primary action can still open its genuine context menu. Pin/Unpin
availability comes from `canChangePin`; the engine builds the menu and executes
its commands while Parc draws the themed menu beside its button. Items an
extension adds to its own button's menu, such as a clipper's Clip this page,
appear right below its name with their checkmarks and submenus, and choosing
one reaches the extension; items it adds only to page menus stay out. Site
Control Center stays open, except for the side-panel item. A disabled row can
show its reason as a tooltip. See [Site Control Center](web-interactions.md).

An extension that declares a side panel, such as a web clipper whose button
opens a popup, also lists Open Side Panel, or Close Side Panel from the moment
its panel starts opening, so a panel that is still loading offers Close and
choosing it closes that panel. When the app hides an open panel's area, the
panel counts as closed at once, so the item says Open Side Panel and choosing
it opens the panel afresh. The label keeps up while the menu is open: moving
to a row or choosing it checks the menu again, so a panel that starts or stops
while the menu shows flips the item's label first, and a click that lands as
its label changes only shows the new label, which VoiceOver also announces.
The engine's own command toggles Parc's native panel, the same panel a toolbar
click or the extension's own open request uses. Choosing it closes an open Site
Control Center first. Pop-up windows keep the item disabled with the tooltip
"Side panels are not available in pop-up windows."

## Held-Command picker

One keyDown/flagsChanged monitor belongs to the original anchor window and its
popover content. Left/Up move backward; Right/Down/physical E move forward,
wrapping the original action order. With no selection, either direction starts
at the first item. Command release and Return select. Other key-downs cancel
and are consumed; keypad Enter is not Return here. A modifier change while
Command remains held cancels and passes through.

The original window, active app, anchor and sheet state are checked before keys
are consumed. Repeated begin advances the same gesture, never adding a monitor.
Deactivation/detachment clears state; close/deinit removes monitors. Immutable
action leases captured at begin prevent a same-ID unload/reinstall from
retargeting Command release. Native page/Profile/security validation still runs.

## Focus and accessibility

Pinned actions are native key-view stops with surface-matched rounded focus
masks. Hidden, detached or invalid actions reject press/menu and report disabled.
Mouse tracking retains its original lease; hide, detach and key-window loss
cancel pending press feedback.

Accessibility uses the genuine action name and Show Menu operation. Policy-
allowed Pin/Unpin remains available as a custom action even before its hover
badge appears. Decorative rings and alternate-click wrappers are not duplicate
accessible elements. Actual extension popup/side-panel contents retain their
native host/window focus; there is no second shortcut dispatcher into web content.

The native toolbar builds its badge-free icon from Chromium’s public icon factory
and image source, preserving disabled and blocked-action decoration. The shell
continues to draw badges in the extension’s own colors.

## Checks

Inert extension-control and Site Control Center components cover action/menu
leases, invalidation, hide/detach, labels, focus bounds, compression, physical
picker keys and wrap/empty selection. Swift checks cover integration.
