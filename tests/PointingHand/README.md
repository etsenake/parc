# Pointing hand

Every Parc button and clickable control shows the pointing hand while a click
on it does something. Tabs, menu rows, the bookmark picker's list in setup and
click-to-dismiss backdrops keep the arrow.

## How controls get it

AppKit controls subclass the `PointingHand…` classes in
[PointingHand.swift](../../Sources/Parc/PointingHand.swift). Each one asks
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
