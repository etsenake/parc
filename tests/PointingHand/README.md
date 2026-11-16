# Pointing hand

Every Parc button and clickable control shows the pointing hand while a click
on it does something. Tabs, menu rows, the bookmark picker's list in setup and
click-to-dismiss backdrops keep the arrow.

## How controls get it

AppKit controls subclass the `PointingHand…` classes in
[PointingHand.swift](../../Sources/ParcApp/PointingHand.swift). Each one asks
for cursor updates over itself and sets the hand while it is enabled.

SwiftUI controls use `.pointingHandCursor()`, inside their button style or on
the clickable view. The modifier asks SwiftUI for its link pointer on macOS 15
and later. SwiftUI's hosting view answers cursor updates itself, and macOS sends
those updates to the view under the pointer, which for SwiftUI content is the
hosting view, so a cursor rectangle alone can be turned back into the arrow
when the pointer crosses another view's tracking area. The modifier keeps the
cursor rectangle as well, which macOS 13 and 14 rely on. Both follow the
control's enabled state.

The update banners' controls get the same link pointer from their own key-stop
modifier, described in [software updates](../../docs/software-update.md#update-complete).

## What the check enforces

`check.py` reads `Sources/ParcApp` and fails when:

- an AppKit button, pop-up button, switch, segmented control or colour well
  doesn't use its `PointingHand…` class, unless it is listed with its reason;
- a view with a tap or long-press gesture, or any gesture except a drag,
  magnify or rotate one, has no `.pointingHandCursor()` among its own
  modifiers, a custom button style has none in its body, or a button with a
  built-in style has neither it nor the update banners' key-stop modifier
  within its surrounding lines, unless the view, style or file is listed with
  its reason;
- the helper or its cursor rectangle loses a line that connects
  `pointingHandCursor()` to the modifier, applies the pointer style, adds the
  rectangle, lets clicks through or follows the enabled state.

A view's own modifiers are the calls chained on it at its own bracket level, so
a hand on a neighbouring view, or inside an overlay's or closure's arguments,
doesn't count for it, while multi-line closures between the hand and the
gesture don't hide it.

It then runs the same rules on broken copies of the helper and on small probe
views, and each must fail with the expected message, or the check fails. Probe
views that are correct, such as a hand placed before a multi-line modifier,
must pass. Run it with `python3 tests/PointingHand/check.py`; `scripts/test.sh`
runs it too.
