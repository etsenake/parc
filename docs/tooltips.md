# Tooltips

`Tooltip`, `TooltipView` and the window-owned `TooltipController` implement
native contextual help. A control's label and accessibility action remain
meaningful independently of its transient tooltip.

## Using it

For a live command shortcut:

```swift
LiveShortcutToolTip.set(button, "Go back", commandID: "goBack:")
```

For a custom anchor, assign `view.parcTooltip` a `TooltipConfiguration`; SwiftUI
uses `.parcTooltip`. Configuration defaults to bottom-trailing placement,
0.45-second idle delay, maximum width 296 and no allowed modifiers. Optional
fields select an anchor rectangle, palette, shortcut requirement and style:
standard or label/subtitle.

A live binding is reread when the tooltip appears. A shortcut-only configuration
shows nothing when the command is unbound. Assignment clears the system tooltip
and owns one tracker; assigning nil removes it. A view updating tracking areas
must remove only its own areas, not another component's tooltip tracker.

### SwiftUI controls

The modifier supplies a native anchor overlay which is hidden from accessibility
and passes input through. The controller's bounded hit test identifies the
actual visible control rather than admitting its whole overlay rectangle.

## The pill

Standard content uses 12-point medium system text, minimum height 28, ten-point
horizontal insets and a six-point label/keycap gap. Radius is 14, with a
three-point cursor-facing/diagonal corner. A dark pill has a one-point white
10% stroke. Shadows use black at 18%/radius 2.5 and 15%/radius 10, offset down
2.5. A 32.5-point rendering margin keeps shadows device aligned.

### The label style

Title and subtitle use 15- and 14-point text, subtitle opacity 0.66 and up to
four lines. A label taller than 28 points has seven points of anchor overhang.

### The dock item tooltip

A dock Space item uses the standard pill with the Space name. Numbered shortcuts
resolve from their live binding instead of a copied key string.

### Copy Quote as URL

The tooltip shows the action title and current keys. It does not introduce a
cloud preview image or placeholder. Accessibility keeps the specific action
label rather than relying on a tooltip to name the control.

## Keycaps

Modifiers appear in Control, Option, Shift, Command order, followed by the key.
Caps have three-point gaps and minimum 19 × 19 size. The base has a 10% black
gradient and radius four; the face radius is three with 1/1/2.5-point insets.
Pressed state reduces the bottom inset to one with a 0.12-second ease. Glyphs
are ten-point bold with two-point padding.

Space displays `⎵` and speaks “Space”. Named keys and function keys retain their
proper labels. Matching uses `charactersIgnoringModifiers`; Shift-transformed
punctuation remains a known matching limitation.

## Colours

Explicit configuration wins over the owning window's palette, then neutral
fallback. App appearance is not forcibly replaced by sidebar appearance.

| Neutral role | Light | Dark |
| --- | --- | --- |
| Title/glyph | Black | White |
| Background | White | White 0.17 |
| Key face | White 0.90 | White 0.28 |
| Key base | White 0.66 | White 0.45 |

Theme title/background use the corresponding appearance. Key surfaces use the
light palette's hover/focus colors and maximum-contrast glyphs in both modes.

## Window and placement

Each parent has one borderless transparent child panel above it at level 25.
It ignores mouse input, cannot become key/main and is absent from accessibility.
Placement uses the screen containing most of the anchor, with fallback to the
parent screen. Edge spacing is four points, clamped eight points inside screen
bounds. Diagonal anchors overlap by six; cursor placement offsets by 12.

Choose the nearest fitting fallback among edge/cursor placements. If none fits,
show nothing rather than placing the tooltip off-screen.

## Motion and the controller

The entered-view stack chooses the innermost actual hit. Mouse buttons and
unapproved raw modifiers, including Caps Lock, suppress presentation. Eligible
ancestors must belong to the key window.

- Initial hover waits for pointer stop (0.08 seconds) plus the configured idle
  delay. First display appears immediately after admission.
- Warm replacement fades in over 0.05 seconds and can replace a fading tooltip.
  A cursor tooltip reopened within 0.6 seconds waits only 0.01 seconds.
- A 0.25-second backstop rechecks admission. Normal hide fades for 0.3 seconds;
  cursor, mouse-down, scrolling and Escape use 0.1 seconds.
- A matching shortcut holds feedback for 0.25 seconds, then fades for 0.3.
  Other keys update held keycaps.
- Animation generations prevent an old completion from removing a replacement.
  Closing the parent removes the tooltip immediately.

Disabled-extension explanations use `TooltipPresenter` with a common-mode timer
so the native custom menu loop cannot starve its delay.

## Adoption

Browser chrome, sidebar actions and custom overlays use the shared component.
Native Settings/onboarding/dialog/menu help remains where appropriate. Existing
controls keep their actions and accessibility labels when help is added.

### Tab rows

A row uses a cursor tooltip after 1.5 seconds, with its title and rename hint
until a custom title exists. The title updates with the actual row and lifetime;
stale hover state must not describe a replacement item.

### Accessibility help

`bindHelp` updates the view and native control cell with the current command
binding. Conflict removal, reset and unbinding update help immediately. SwiftUI
`.help` is used only on its intended route. Named action labels remain available
when no tooltip is showing.

## Checks

`python3 tests/Tooltip/check.py` covers configuration, layout, live bindings,
placement, timing and invalidation through native components and injected events.
