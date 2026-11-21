# App icon picker interaction

`IconSettingsView.swift` presents one native radio button per approved icon.
`AppIconController` owns selection, atomic persistence, native identity and
Finder retry. The picker scales the controller's image proportionally inside a
64-point frame; it does not crop, recolor or produce a competing export.

## Presentation

Rows are 81 points high with a 14-point title and an accent-colored **CURRENT
ICON** marker after the title. Changing selection does not shift the title.
The row and artwork stay at resting scale during hover and press; only the
radio indicator uses pressed feedback. The pane has no hover spring or delayed
selection timer. Artwork and labels are decorative accessible children; the
named row is the single radio element inside a named group.

## Native control adaptation

The full row is clickable. Mouse-down arms it, dragging out disarms it, dragging
back re-arms it, and release inside performs one action. Both bounds and
`visibleRect` must contain the pointer. Space, Return and keypad Enter arm on
key-down and commit on matching key-up; repeats and stray releases do not save
again. Escape cancels. Unmodified arrows focus, reveal and select an adjacent
row, stopping at the ends. The selected row is the group's Tab entry.

The focus ring covers only the radio indicator and requires first responder,
a key original window and an active app. Focus loss, hiding, detachment,
disabling, window closure/key loss, app deactivation and external selection
changes cancel unfinished input. Window observers are removed on detachment
and deinitialization. Retained closed Settings windows reject stale actions.
Callbacks capture owners weakly; there is no global event monitor or timer.

The native button never toggles optimistically. After a pointer, keyboard or
accessibility action, it rereads the controller. Failed persistence leaves the
old radio value and current marker intact, with status and retry owned by the
controller.

## Checks

`IconSettingsTests` (`tests/ParcTests/Data`) run the picker and controller with
disposable preferences, an injected identity recorder and an unshown window.
Coverage includes hit testing, press/release/cancel, focus/repeat, accessibility
role/value/action, persistence failure, attachment and window interruption.
See [availability](app-icon-availability.md) for the catalog policy.
