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
its commands while Parc draws the themed menu beside its button. Site Control
Center stays open. A disabled row can show its reason as a tooltip. See
[Site Control Center](web-interactions.md).

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
