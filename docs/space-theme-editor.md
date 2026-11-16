# Space theme editor presentation

`SpaceThemeEditorView` is shared by Space editing, Space creation and onboarding.
It owns pad/swatches/intensity/noise presentation. [Theme input](space-theme-input.md)
owns gestures, [appearance](space-theme-appearance.md) owns parent policy, and
[theme rendering](space-theme-rendering.md) owns window materials and textures.

## Pad

The pad clips to continuous 8-point corners, fills `labelColor` at 0.05 and tints
its stretched DotGrid at 0.4. Color handles keep their own position/hover springs.
The knob under the pointer keeps its hover growth through a pad drag, including
a grabbed knob and the primary knob arriving under a background drag, so the
growth always matches the open or closed hand. When a knob moves under a still
pointer, through a plain click, an arrow-key nudge, Undo or a theme sync, the
editor rereads the pointer once no gesture is under way and its window is key,
so growth and cursor follow the knob. Pad buttons suppress hover while a knob is
hovered or dragged, restoring that state from the actual pointer after
cancellation.

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

While the pointer is over the track, or a drag holds the thumb, it swells 5%,
matching the editor buttons, and its shadow deepens from 5% opacity with a
1.5-point blur and 2-point drop to 12%, 4 and 3. The swell uses the buttons'
0.1-second ease, hover scale and `ThemeButtonMotion`, so Reduce Motion settles it
at once. The control draws with 4 points of room on each side and 10 above and
below its old 240 × 60 frame, so the swollen thumb and shadow fit at full
intensity; clicks, hover and the accessibility frame keep the old band.

## Noise dial

The control is 80 × 80 with a 40-point circular texture center and 1-point separator
ring. The texture is drawn at 1.2× and 0.6 opacity inside that fixed circle; only
the texture scales for hover/press. Hover tracks its square frame, while a held
press must remain inside the circle. Wheel eligibility changes immediately.

Nineteen 5-point dots lie on a 32-point radius at 18-degree increments, leaving
the bottom slot empty. Lit dots overlay foreground ink on separator ink, counting
clockwise from the top. Each dot fills as the marker turns past it: its ink fades
in over the twentieth of a turn from its own step to the next, so the ring's ink
grows continuously with the value; the empty bottom slot adds none. The marker
covers the dot it sits on, so the filling shows on the dot just behind it.

The marker is an 8 × 16 white radial capsule. Over the ring, where the open hand
shows, and while a drag or rotation is turning the dial, it swells and deepens
its shadow exactly like the slider thumb, moving inward so its tip stays inside
the dial. It draws in its own non-interactive layer beside the dial, 8 points
larger on every side, so its shadow draws in full at every angle while the dial
keeps its frame, clicks, hover and VoiceOver outline. Hovering the centre knob
grows only the texture. Gesture admission and
wheel/rotation cancellation are in [theme input](space-theme-input.md).

## Preset start page

Each browser window starts on preset page 0 and remembers its most recent page
for both Space and Space-creation editors. `themeEditorPresetPage` and
`onPresetPageChange` keep that state window-local; it is not persisted. Onboarding
starts at 0. Disabled arrows use 0.33 opacity.

## Tooltip colours

`onTooltipThemeChange` publishes the displayed theme on window attachment and
on later preview/commit/Undo changes. The original popover window's
`TooltipController.palette` follows it, and a tooltip already on screen repaints
in place. Onboarding does not install that callback.

## Tooltip adoption

Swatches, arrows, add/remove, appearance and noise controls use the shared Parc
tooltip below the control and inherit their popover's palette. Noise lives on a
tooltip anchor covering the centre knob's square frame, the same region that
shows the pointing hand, so the ring and corners stay quiet while you line up a
drag. The anchor passes every click and drag through to the dial.

## Checks

Theme rendering/input/appearance/Undo components cover actual control constants,
button reversal, disabled drawing, cancellation, native parent identity and
palette propagation.
