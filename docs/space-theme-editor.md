# Space theme editor presentation

`SpaceThemeEditorView` is shared by Space editing, Space creation and onboarding.
It owns pad/swatches/intensity/noise presentation. [Theme input](space-theme-input.md)
owns gestures, [appearance](space-theme-appearance.md) owns parent policy, and
[theme rendering](space-theme-rendering.md) owns window materials and textures.

## Pad

The pad clips to continuous 8-point corners, fills `labelColor` at 0.05 and tints
its stretched DotGrid at 0.4. Color handles keep their own position/hover springs.
Pad buttons suppress hover while a knob is hovered or dragged, restoring that
state from the actual pointer after cancellation.

## Preset swatches

Each swatch fills 24 × 24 points with a 2-point black 0.1 inset border. Pressed
feedback uses the existing 0.22/3-point border. It is distinct from general
editor button motion.

## Button style

Appearance, add/remove and preset-arrow buttons use:

- Press scale 0.9 with response 0.3/damping 0.5 spring.
- Hover scale 1.05 and secondary-label fill at 0.2, over 0.1-second ease-out.
- Continuous 8-point clipping and disabled opacity 0.33.
- Pointing-hand cursor and real native action/keyboard/accessibility ownership.

`ThemeButtonMotion` preserves velocity across reversals. A 60-Hz common-mode
timer runs only while unsettled. Reduce Motion, detached controls and changes
while outside a window settle immediately. Press tracking rereads the pointer
so dragging out drops hover and dragging back restores it.

Appearance buttons have 32-point frames and a selected background. Preset arrows
use 16-point semibold symbols in label color at 0.6, resolved under the current
appearance. Replay onboarding enables appearance selection as first launch does.

## Intensity slider

The slider's 224 × 44-point wave has 8-point padding, 5-point stroke and frequency
`2π − 0.25`. Its leading region overlays a 16-point capsule and foreground wave.
The white thumb starts 12 × 44 and grows by 15 × value in both dimensions. Dark/light
appearance changes its faint shadow and the track colors, not the white thumb.
The current implementation draws the resting thumb/shadow without hover growth.

## Noise dial

The control is 80 × 80 with a 40-point circular texture center and 1-point separator
ring. The texture is drawn at 1.2× and 0.6 opacity inside that fixed circle; only
the texture scales for hover/press. Hover tracks its square frame, while a held
press must remain inside the circle. Wheel eligibility changes immediately.

Nineteen 5-point dots lie on a 32-point radius at 18-degree increments, leaving
the bottom slot empty. Lit dots overlay foreground ink on separator ink, counting
clockwise from the top. The current drawing lights whole twentieth steps rather
than partial dots. The indicator is an 8 × 16 white radial capsule; its shadow also
uses resting values. Gesture admission and wheel/rotation cancellation are in
[theme input](space-theme-input.md).

## Preset start page

Each browser window starts on preset page 0 and remembers its most recent page
for both Space and Space-creation editors. `themeEditorPresetPage` and
`onPresetPageChange` keep that state window-local; it is not persisted. Onboarding
starts at 0. Disabled arrows use 0.33 opacity.

## Tooltip colours

`onTooltipThemeChange` publishes the displayed theme on window attachment and
on later preview/commit/Undo changes. The original popover window's
`TooltipController.palette` follows it. An already shown tooltip keeps its
presentation colors until shown again. Onboarding does not install that callback.

## Tooltip adoption

Swatches, arrows, add/remove, appearance and noise controls use the shared Parc
tooltip below the control and inherit their popover's palette. Noise anchors to
`knobRect`; the tooltip hit region currently remains the whole dial.

## Remaining presentation limits

The intensity thumb/noise indicator do not grow their shadow/scale on hover.
During a pad drag, entering a handle changes the cursor without refreshing its
hover scale. Noise uses whole lit dots during continuous rotation, and its
label can trigger outside the center knob.

## Checks

Theme rendering/input/appearance/Undo components cover actual control constants,
button reversal, disabled drawing, cancellation, native parent identity and
palette propagation.
