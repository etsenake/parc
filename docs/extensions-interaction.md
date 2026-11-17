# Extension interaction — EXT13

The shell retains real profile/browser/page action leases. An extension ID
selects presentation; it never authorizes a replacement extension instance.
Installation, commands, permissions and services stay with Chromium's owners.
See [extensions](extensions.md) and [lifecycle](extensions-lifecycle.md).

## Controls

Pinned sidebar actions use a 28-point surface, 9-point corners and 16-point icon,
GrayA4 hover and GrayA5 press. Press scales to 0.95 with response 0.3/damping 0.6
from the current presentation transform. Top-bar actions use 32 × 24 points and
6-point corners, with hover fill but no sidebar press spring, and light with the
page toolbar's own press fill, so they match the Site Control Center button
beside them in light and dark. The actual engine supplies decorated artwork,
tooltip and accessible name.

The button a popup belongs to stays lit with the press fill, like a menu button
while its menu shows, from the moment its popup starts until the popup starts
fading away. That's the clicked button, or for a popup opened by a shortcut, the
command bar or the extension itself, the button it
[anchors to](extensions-geometry.md#popup-anchor): the extension's pinned
button, else the Site Control Center button, in the sidebar, any pane or a
pop-up window's chrome. The fill eases in over 0.18 seconds and out over 0.15
seconds alongside the popup's own fade. A popup that's refused, fails or closes
before it appears lets go at once, a replacing popup takes the light to its own
button, and a popup that moves to another anchor brings it along. While the
popup loads, the icon hops like a launching Dock icon: a springy 3-point rise
and soft landing every 0.7 seconds, starting after 0.18 seconds so a popup
that's quick to appear doesn't hop at all. When the popup appears the icon
finishes its current hop and lands; a failure brings it straight down in 0.14
seconds. A pinned badge hops with its icon. Reduce Motion drops the hop and
keeps the light. VoiceOver hears the button as expanded while it's lit. The
rules live in [`ExtensionPopupActivity`](../Sources/ParcApp/ExtensionPopupActivity.swift).

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
picker keys and wrap/empty selection. The windowless popup activity check
(`tests/ExtensionPopupActivity/check.py`) covers which button lights, its
handoff and release, the fill's fade and the hop's rhythm, landing and Reduce
Motion. Swift checks cover integration.
