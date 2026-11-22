# ParcKit

ParcKit is the shared interface toolkit: the controls, dialogs, tooltips,
toasts, theme drawing, sounds and keyboard shortcut model that more than one
feature uses. It holds no feature screens and no browser state of its own;
when a control needs to know about the app, such as which shortcut a command
has, it asks through a closure the app fills in. It sits just above ParcCore in
the [app architecture](../../docs/app-architecture.md), so every feature
library can use it.

## Where to start

**Controls.** [PointingHand.swift](PointingHand.swift) holds the controls that
show the pointing-hand cursor (`PointingHandButton`, `PointingHandPopUpButton`,
`PointingHandSwitch`, `PointingHandSegmentedControl` and
`PointingHandColorWell`); feature buttons subclass the first two.
[ActionButton.swift](ActionButton.swift) is the closure-driven button,
[TranslucentButtonFace.swift](TranslucentButtonFace.swift) draws Parc's
translucent buttons, [LayoutView.swift](LayoutView.swift) and
[FlippedStackView.swift](FlippedStackView.swift) are layout helpers, and
[LocalContentDrop.swift](LocalContentDrop.swift) gives views and text views a
shared way to accept dropped files.

**Dialogs, tooltips and toasts.** [ParcDialog.swift](ParcDialog.swift) builds
Parc's dialogs and their buttons and checkboxes.
[TooltipController.swift](TooltipController.swift) shows Parc's own tooltips,
with their look in [Tooltip.swift](Tooltip.swift) and
[TooltipView.swift](TooltipView.swift). [ParcToast.swift](ParcToast.swift)
models, queues and presents toasts, with an injectable clock.

**Theme and appearance.** [ThemeRenderer.swift](ThemeRenderer.swift) draws a
Space's theme behind the window chrome and computes its palettes;
[AppAppearance.swift](AppAppearance.swift),
[NSColor+Parc.swift](NSColor+Parc.swift),
[ParcMenuColors.swift](ParcMenuColors.swift) and
[SidebarRowAppearance.swift](SidebarRowAppearance.swift) hold shared colours
and row styling. [InterfaceFeedback.swift](InterfaceFeedback.swift) and
[ThemeHapticFeedback.swift](ThemeHapticFeedback.swift) play interface sounds
and haptics. The artwork files (`…Artwork.swift`,
[ParcBrandMark.swift](ParcBrandMark.swift)) draw shared icons.

**Keyboard and focus.** [KeyboardShortcuts.swift](KeyboardShortcuts.swift)
holds the `KeyboardShortcut` model, the shortcut catalogue and the main menu's
key equivalents. [TextFormatMenu.swift](TextFormatMenu.swift) maps text
formatting commands to keys, and [SavedFocus.swift](SavedFocus.swift) decides
whether keyboard focus may return to a view and whether a hidden view is
presented for editing.

**Motion and layout support.**
[ViewDisplayFrameDriver.swift](ViewDisplayFrameDriver.swift) drives per-frame
updates from the display, [HistorySwipeTargets.swift](HistorySwipeTargets.swift)
works out which page or Easel a back or forward swipe acts on, and
[EaselCaptureLayout+Native.swift](EaselCaptureLayout+Native.swift) lays out
captured pages for Notes and Easels.

## Imports and hooks

ParcKit imports ParcCore for the models its controls display and ParcEngine for
the few places that talk to the engine: the keyboard shortcut catalogue,
FairPlay identity and native capture layout. Everything other libraries use is
`package`, except the base classes they subclass across libraries, which are
`open` and declare `Sendable`.

The app fills in these hooks at launch, in `AppDelegate`:

- `TooltipController.commandShortcut`, `eventChord` and `symbolicChord` look up
  the shortcut a tooltip shows.
- `LiveShortcutToolTip.binder` and `resolver` attach live shortcut text to a
  view's tooltip.
- `KeyboardShortcuts.onDiscoveryChange` tells tooltips that shortcut discovery
  changed.

Controls such as `ActionButton`, `LayoutView`, `PopoverBackgroundView` and the
toast state take closures from whichever view owns them.

## Tests

Tests for ParcKit's controls live in [tests/ParcTests](../../tests/ParcTests/README.md),
mostly in Presentation (dialogs, toasts, theme rendering, interface feedback),
Sidebar, CommandBar (shortcuts and tooltips) and Windows. Run one suite with
`swift test --filter ParcToastTests`, or everything with `swift test`. See the
[testing guide](../../docs/testing.md).

## Behaviour guides

- [Tooltips](../../docs/tooltips.md), [toasts](../../docs/toasts.md) and
  [dialogs](../../docs/dialogs.md)
- [Keyboard navigation](../../docs/keyboard-navigation.md)
- [Space theme rendering](../../docs/space-theme-rendering.md) and
  [haptics](../../docs/space-theme-haptics.md)
- [Swipe navigation](../../docs/swipe-navigation.md)
