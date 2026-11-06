# Space theme editor presentation

This covers how the shared `SpaceThemeEditorView` draws and lays out its pad,
preset swatches, intensity slider and noise dial, which preset page it opens
on and how its window's tooltips are coloured. Pointer, rotation and wheel
contracts are in [theme input](space-theme-input.md), the appearance buttons
in [appearance parent](space-theme-appearance.md), and the window gradient and
grain in [theme rendering](space-theme-rendering.md#texture-alpha-october-31).

## Evidence

`4e452201e483b5480c0403a9ef8566e10515cdcb78828622ff9032b202e29547`, read with
the annotated-function, type and cross-reference helpers only. Named color
used as an asset reference only. Measurements come from the user's October 31
356-point picker width. Tags: [D] recovered from the binary, [O] observed or
measured, [I] inferred, [C] an inert local check.

[O] BaseAssets values used below:

| Name | Dark | Light |
|---|---|---|

## Pad

  template `DotGrid` image (stretched) over it at 0.4 opacity, clipped to a
  continuous rounded rectangle. Parc fills `labelColor` at 0.05 and tints the
  grid with `labelColor` at 0.4.
  pad layer now clips at 8 points with a continuous corner curve (it was 6),
  applied after the pad drag fix landed (`a69d649c`).

## Preset swatches

  2-point `Color.black.opacity(0.1)` border in multiply blend mode. Multiply
  with black equals source-over at the same opacity. Parc fills the whole
  24-point frame and strokes the border inside it. Its pressed 0.22/3-point
  border is Parc's existing feedback.

## Button style

  `isEnabled` (environment), `hoverColor` and `hoverStyleEnabled`. Its body is:

  ```text
  label
    .scaleEffect(isPressed ? 0.9 : 1)
    .animation(.spring(response: 0.3, dampingFraction: 0.5), value: isPressed)
    .background(hovered ? hoverColor : .clear)
    .scaleEffect(hovered ? 1.05 : 1)
    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    .opacity(isEnabled ? 1 : 0.33)
    .customCursor(.pointingHand)
  ```

  `hovered` is `isHovered && hoverStyleEnabled && isEnabled`. The hover
  closure sets `isHovered` inside `withAnimation(.easeOut(duration: 0.1))`
  content and fill stay inside the unscaled 8-point frame shape.
  style for a control:

  | Control | Builder | `hoverColor` | `hoverStyleEnabled` |
  |---|---|---|---|

  for the same buttons with their `disabled` modifier. The swatches use
  `ColorPillButtonStyle` instead.
- [D] `LightDarkToggleView.shouldEnableButtonHover` is
  pad's own state. [M] `EditColorButtonsView` takes the same field; [I] its
  value is the same expression.
  in the hover colour, in the same 8-point continuous shape, framed 32 × 32.
  `.font(.system(size: 16, weight: .semibold))` (the lazy 32 × 0.5, design
  nil), `.frame(width: 32, height: 32)` and
  `.foregroundColor(Color.primary.opacity(0.6))`. [C] SwiftUI resolves that
  colour to labelColor with its alpha × 0.6: white or black at 0.508
  normally. Parc resolves labelColor per appearance and multiplies its alpha
  the same way, so Increase Contrast carries through.
- Parc: `ThemeButtonMotion` holds the press scale and the hover share
  (0 to 1). It runs the press on that spring, keeping velocity across
  reversals, and the hover on easeOut's cubic Bézier. `ThemeButtonMotionDriver`
  advances it on a 60 Hz `.common` timer until both settle. Reduce Motion, or
  a control outside a window, applies changes without motion. Reduce Motion
  switched on mid-animation settles it at once.
  `ThemeButtonStyle.draw` composes the body above in AppKit:
  - it clips to SwiftUI's own continuous `RoundedRectangle` path;
  - it scales the content about the frame centre;
  - its hover fill is `secondaryLabelColor` at 0.2 of its alpha, times the
    hover share;
  - it draws a disabled control in a 0.33 transparency layer.
- The appearance buttons, − and + and the chevrons share the motion model
  and `ThemeButtonStyle.draw`. The knob shares only the motion model: it
  applies the scale to its texture inside its own circle clip and ring.
- The pad sets its buttons' `hoverStyleEnabled` from whether a knob is under
  the pointer or being dragged. A cancelled pad gesture restores it from the
  actual pointer. Enabled-state and hover-style changes apply without motion
  [I], and redraw only when they change.
- NSButton's press tracking holds back the tracking area's exit and entry, so
  `highlight(_:)` re-reads the pointer, as the sidebar's `ActionButton` does.
  A press dragged off a button drops its hover and one dragged back on
  restores it. Leaving the window clears a button's hover with its motion.
  Onboarding removes the editor and adds it again on Back.
- The
  0.05/0.1/0.15 fills and 7-point corners are gone. The chevrons are framed
  32 × 32 around their previous centres, where they were 28 wide. They draw
  the symbol at 16-point semibold, medium scale, in labelColor × 0.6.
  Before, they used the default symbol in `secondaryLabelColor`.
  centres sit about 2.5 points lower in that crop. Its peak contrast over its
  own backdrop is 0.49, against Parc's 0.46 offscreen; the popover material
  isn't rendered offscreen.
- [I] Where a pad button overlaps a knob, the knob counts as hovered for the
  buttons' hover styling, since an AppKit tracking area doesn't depend on
  z-order. So neither shows hover there, and the button still takes the click.

### Questions on the button style

- Does the knob's circle clip sit outside the style, so the circle stays 40
  modifiers applied to the Button, so the circle and ring stay 40 points while
  the texture scales. This wasn't seen at runtime.
- Does the style's hover keep tracking during a drag? [D] Yes. Its hover comes
- Is the knob's hover set outside any animation? [D] The dial has two. Its
  with no animation; it gates the wheel. The style's own `isHovered`, which
  drives the 1.05 scale and fill, is set inside
  wheel at once and animates the scale.
  since November 2: Parc's replay enables them as first launch does
  ([appearance parent](space-theme-appearance.md)), so the editor no longer
  ever disables them wasn't traced.

## Intensity slider

  padding, a 12 × 44 thumb and 15-point value growth, as before.
  `SidebarSeparator`, with frequency `2π − 0.25`.
  points tall filled with `SidebarSeparator` at 0.5 opacity, plus the wave in
  `SidebarForeground`, framed to the thumb position
  `padding + (width − 2 × padding) × value`.
- [I] The leading layer lies over the base wave, so the lit wave composes to
  track about white 0.075 over 16 points.
- [D] The thumb is `Color.white` in both appearances. Its shadow is `(dark ? white
  : black).opacity(0.05)`, radius 1.5 (3 hovered) and y 2 (4 hovered). Hover
  scales it 1.1 with spring(0.25, 0.9). Parc draws the resting thumb and shadow.
  In Light, then, the thumb and the dial indicator stay white, and only their
  faint shadow turns black. The wave's base is black 0.15, and its leading part
  composes to about black 0.405.
  center line. Parc's slider frame moves from (16, rowY + 52) to (10, rowY + 56),
  so the native 224-point slider starts at 18 and centers at 452.

## Noise dial

  Parc's control is 80 × 80, centered where the 76-point frame was (298, 452).
  circle and drops its earlier secondary-label underfill.
- [D] The knob is the label of a centre `Button`. The label's type name
  Image, _OpacityEffect>, _ScaleEffect>, _FrameLayout>`. So the (0.6, 1.2) pair
  about the centre, inside the half-dimension frame. The Button is then
  So the texture is magnified 1.2× within the 40-point disc. Parc draws the
  image into a 48-point square centred on the knob, at 0.6 opacity, clipped to
  the 40-point circle. Its hit geometry is in
  [theme input](space-theme-input.md#knob-hit-geometry-november-1).
  image at full opacity, which fits the 0.6 opacity.
- [D] The centre Button uses the [button style](#button-style) with
  `Color.clear` as its hover fill and hover styling on
  outside the style, so they keep their 40 points. Only the texture zooms:
  1.2 × 1.05 while hovered, × 0.9 while pressed.
- Parc sets the knob's hover from the 40-point square frame, including during
  that began on the knob stays inside its circle.
  offset (0, 32) and rotated by `index × 18°` from the bottom. So 19 dots draw
  and the bottom slot stays empty. Parc previously drew 21 dots at 4.6 points.
- [I] The second loop is masked by a 6-point square-cap ring (`StrokeStyle` at
  clockwise from the top to the value. Parc lights whole dots in integer
  steps: dot step `(index + 10) mod 20` counts from the top, and a dot is lit
  when `step ≤ value × 20`.
  - That is equivalent at the model's twentieth steps.
  - A zero value lights nothing, as a zero-length trim would; the indicator
    covers the top dot there anyway.
  - Partially lit dots during continuous rotation are not reproduced.
- [D] The two `ForEach` content closures pass colour accessors to the dot
  colour, and the lit ones are drawn again on top in the foreground colour.
  - Dark: lit dots compose to 0.45 + 0.15 × 0.55 = 0.5325, against the
    screenshot's 0.54, and unlit dots to 0.15, against 0.16.
  - Light: lit dots compose to black 0.405 and unlit dots to black 0.15.
  - Parc draws the dots the same way. It previously used ForegroundSecondary
    (0.5) for lit dots.
  with the thumb's shadow and hover values. [O] It centers on the 32-point dot
  radius, with its long axis radial. Parc's 6-point round stroke is replaced.
  traced to its target. Parc keeps the clockwise-from-top placement of the
  recovered pointer mapping, which the screenshots show.

## Preset start page

- [M] `SpaceStyleEditor.State.currentPresetPage` (field 11, State offset
  argument. The editor's chevrons don't page by themselves: they send
  `Delegate.didTapPreviousPresetPage` or `didTapNextPresetPage`.
  passes a literal 0. The other three pass the window's page, read through
  callers are:
    and the window reducer. It builds the editor state that
    `SpaceCreation.State.spaceStyleEditor` embeds. It then stores
    `SpaceCreation.State?` into `WindowState` (+0x308) through `WindowData`
    editor after a theme Undo.
- [M] `SpaceCreation.Action.Delegate.spaceStyleEditor` forwards the editor's
  delegate actions, including the page taps, to the window.
  `currentThemeEditorPresetPage -= 1` and `+= 1` (overflow-checked, no clamp;
  the chevrons are disabled at the ends). It then writes the page into the
  presented editor's state.
  `CodableWindowData`, the on-disk window record, has no such field, and
  `PersistedWindowState` is not Codable.
- So a new window opens the picker on page 0 (solid Brand). The user's
  screenshots show that, with "<" dimmed. The window then reopens on
  whichever page it last showed, in both the Space and Space-creation
  editors. Parc's `BrowserWindowController` keeps `themeEditorPresetPage`
  (starting at 0) for both. It passes the page to `SpaceThemeEditorView(theme:presetPage:)`
  and takes changes back through `onPresetPageChange`. Onboarding creates the
  editor with the default page 0 and keeps nothing. Parc previously opened
  every editor on page 1 (three-colour Brand).
- [D] The chevrons use the [button style](#button-style), so a disabled
  chevron draws its enabled look at 0.33 opacity. AppKit's own disabled
  dimming, which Parc used before, left about 0.54 of the enabled contrast.
  gradient lightens the backdrop on the left: about 0.325 behind "<", against
  0.208 behind ">". Measured as contrast over its own backdrop, "<" is 0.358 of
  same chevron enabled.

## Tooltip colours

  palette (offset `0x88`). Tooltips inside the editor's popover therefore take
  that palette whenever their configuration has none.
- [M] The controller's `ViewState` is `(editorState, tooltipColorPalette)`.
  `SidebarSpaceState.themeContext.theme` (field 24, a `WindowThemeContext`
  whose first field is the 273-byte `WindowTheme`). It maps that through
  state change while `spaceStyleEditor` (field 23) is set.
- [I] The palette is the edited Space page's own theme, so it follows the live
  edit.
  tooltip configuration its palette, but it is this editor popover's
  `ViewState` scope.
- Parc: `SpaceThemeEditorView.onTooltipThemeChange` reports the shown theme
  when the editor arrives in a window. While it stays there, it reports again
  whenever a refresh shows a different theme. That covers previews, commits,
  parent replacement and Undo.
  `BrowserWindowController.makeThemeEditor` sets the popover window's
  `TooltipController.palette` to `TooltipColorPalette(theme:)` from it, for
  the Space and Space-creation popovers. Onboarding sets no closure.
- So the popover window's tooltip controller carries the edited theme's
  palette, and the editor's tooltips take it. A tooltip already on screen
  fixed at present time.

## Tooltip adoption

The app-wide adoption ([tooltips](tooltips.md#adoption)) gives the swatches,
the chevrons, − and +, the appearance buttons and the Noise dial Parc's
tooltip, each below its control. None carries a palette of its own: leaving
`palette` nil inherits the popover window's palette described above.

  `knobRect` through `TooltipConfiguration.anchorRect`, set again whenever the
  dial's frame changes.
- Restricting the hover itself to the knob needs a hit region the tooltip
  controller doesn't have yet, so the whole dial triggers it.

## Recorded gaps

  show its 1.1 hover scale while a pad drag holds it under the pointer. Parc
  changes only the cursor then.
  replay does ([questions](#questions-on-the-button-style)).
- Hover scale and shadow growth for the thumb and indicator are not
  implemented.
  screenshot was compared.

## Checks

`scripts/test-theme-rendering.sh` snapshots the real controls offscreen at 2×.
It checks:

- Dial: the empty bottom slot, 19 drawn dots, and the lit composite of 0.5325
  over unlit 0.15. Also the indicator's radial 8-point capsule, the 40-point
  disc and its reduced opacity. An Aqua snapshot checks black dots at 0.15,
  lit dots at black 0.405 and the white indicator.
- Button motion: `ThemeButtonMotion`'s 0.945 hovered press, the press
  spring's overshoot to about 0.884 and its 0.9 rest, and hover's scale and
  fill easing out together to 1.05 and the full fill at 0.1 seconds. A
  hovered knob snapshot zooms the texture inside the unchanged 40-point
  circle.
- Chevrons: the 32-point frame, and ">" ink in white at about 0.508 in Dark
  and black in Aqua. The first page disables only "<", which
  draws the enabled chevron's peak at 0.33 (0.30–0.37) and shows no hover
  fill. A hovered ">" fills its frame with secondary × 0.2, leaves the
  8-point corner clear and fades the fill out on exit.
- `scripts/test-theme-input.sh` also checks:
  - that a hovered − shows its fill, a hovered knob turns it off and leaving
    the knob restores it;
  - that a press, which re-reads the pointer, drops a hover it is no longer
    over;
  - that a hover from before the editor left its window doesn't come back;
  - that a knob press scales the texture, and a rotation that starts during
    the press releases it for the rest of that press and its release;
  - that pressing ">" draws it at the press scale and releasing restores it.

  The script copies the knob textures so the knob draws.
- `scripts/test-theme-appearance-timer-idle.sh` checks the motion timer:
  - a hover and a press each arm it, and it stops once they settle;
  - a settled button makes no further redraws;
  - Reduce Motion switched on mid-animation settles at once, and under it a
    hover arms no timer;
  - − and + aren't redrawn on each pad-drag frame.
- Slider: the frame, white thumb, the leading track only, and the
  foreground/separator wave.
- Swatches: the full-frame fill and inner border.
- Pad: the 0.05 fill, the 0.4 grid and the 8-point continuous corner.
- Tooltip theme: nothing is reported while the editor has no window. The
  shown theme is reported once on arrival in a never-ordered-in window, not
  again for a refresh that changes nothing, then after a parent replacement
  and after an edit. Arriving again reports even an unchanged theme. Nothing
  is reported after detaching.

The same checks fail against the previous editor drawing. No browser or engine
is loaded.

`scripts/test-theme-appearance.sh` checks the preset page:

- An editor without a window page opens on page 0.
- Each chevron change is reported to the owner.
- A later editor opens on the owner's page.
- The end pages disable their chevron.
- Out-of-range pages are clamped.

The production wiring in `BrowserWindowController` isn't compiled by a
focused check.
