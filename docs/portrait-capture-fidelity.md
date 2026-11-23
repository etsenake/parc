# Portrait controls and rendering

Portion, Visible Area and Full Page share one post-capture editor and output
transaction. Apply and Cancel return to the same preview. Changing a frame never
recaptures the page; removing it restores the original PNG byte for byte.

## Controls and image output

Frame in Portrait Mode pushes a Portrait Frame page inside the capture
palette's card, with a back button, and the captured image beside it becomes the
live preview of the framed result at page size, rendered at exactly the screen
pixels it occupies (the final image itself when that fits) and blended on each
change. The picture reports its pixel size, so a resized window re-renders it.
The page offers Color, Website and
Wallpaper as picture tiles, the chosen one ringed in the Notes accent; the
12-point color track with its 24-point white knob sits under them, and moving it
picks Color. The header's trailing toolbar toggle draws Parc's P: filled in the
Notes checked colour while the "Captured in" line is on, struck through when
off. Its choice is remembered (`parc.capture.portrait.hideWatermark`) and is
a change Apply can commit. Cancel and Apply are Parc's
dialog buttons. Apply is the primary blue button only while there is a change to
apply: always when adding a frame, and after a change when editing one;
otherwise it stays muted. Return applies a pending change or goes back when
nothing changed; Escape, Left on the page, Cancel and the back button return to
the palette. Latest color changes are throttled at 50 ms. `CaptureFrameApply`
holds the Apply rule.

Composition works in device pixels. The captured pixels land in the frame one
to one at whole-pixel positions, whatever the capture's size, so nothing is
resampled. An even margin of `round(0.08 × √(width × height))` logical points,
clamped to 40–160 points and rounded to whole device pixels, surrounds it, so
frames of any shape keep the same share of background and a 1440 × 900 capture
fills about 89% of the frame's width. Easel's image limits bound every frame:
16,384 pixels a side, 80 million pixels and 30 MB. A capture that only fits
with a thinner margin keeps every pixel and gives up margin down to 40 points;
only one too big even for that is scaled, just enough to fit, and a PNG over
30 MB is re-rendered smaller until it fits. Radii, shadow and frame lines follow
the density, and the PNG declares it (144 DPI at 2×, proportionally less for a
scaled frame, so it still opens at screen size). The output is opaque RGB in the
source's RGB profile, or sRGB for anything else, and keeps 16-bit depth for
deeper sources. The wallpaper fills the frame without stretching. Preview and
every destination use the same composition.

The watermark reads "Captured in" followed by Parc's P, centred in the bottom
margin. The text is the system semibold face at 30% of the margin (10–28
points); the P is the `Marks/Monochrome.svg` vector, compiled into
`ParcBrandMark`, 1.3 cap heights tall and standing on the text's baseline. Both
share one ink: black at 0.45 or white at 0.75 around a 0.75 brightness
threshold using sRGB coefficients 0.299, 0.587 and 0.114. Desktop backgrounds
are sampled beneath the whole line. Turning the toggle off omits the line, so
every output renders exactly as a frame without it. Thumbnail and final bitmap
follow the same policy.

## Live desktop and lifetime

Parc's `PortraitDesktopSnapshot` preserves that desktop-window boundary. It
preflights the actual screen-capture permission without requesting or bypassing
it. It requires a wallpaper candidate at or below the system desktop-window level whose bounds exactly match the original
window's display and whose PID/bundle is the system wallpaper producer. The system Dock producer remains supported; current macOS WindowManager's `Wallpaper`
window and Apple's wallpaper process are explicit platform adaptations. Finder,
widgets, other applications, another display and the Dock itself cannot be
substituted. On macOS 14+, the matching ID/PID/frame is revalidated against
ScreenCaptureKit and captured through a desktop-independent single-window
filter. macOS 13 uses the original public CGWindow route. No full-display
fallback exists. Apple's [single-frame screenshot API](https://developer.apple.com/documentation/screencapturekit/scscreenshotmanager/captureimage(contentfilter:configuration:completionhandler:))
replaces the API removed in macOS 15.

One real desktop snapshot is retained by each accepted composition. This shows
current dynamic wallpaper pixels when framing starts while keeping the approved
preview identical to later exports and reframes. It deliberately does not
refresh wallpaper during a slider drag or after Apply. The async result belongs
to that exact frame editor; removal/cancellation increments its generation and
cancels the task, and stale callbacks cannot change another capture. Saved
Desktop preferences wait for the actual image; until then, and after a failure,
the preview shows the unframed capture with the error and Apply stays
unavailable across other refreshes until the user explicitly chooses Color,
Website or the color slider. Denied, absent or failed desktop
capture leaves a descriptive error/help and usable Website/Color choices;
missing desktop pixels never silently render a different background.

## Checks and boundaries

The compositor/CapturedImage checks cover original/cropped PNG preservation,
reversible framing, tall images, 2× and 3× density declared in every PNG,
captured pixels kept exactly at odd sizes, 2×, 3×, wide gamut and sizes beyond
any screen, Easel's pixel and byte limits, previews sized to their screen
pixels and the picture's one-to-one display,
margin geometry across shapes, Display P3 conversion, the watermark toggle's
output and remembered choice, caption and mark placement, watermark thresholds,
desktop candidate filtering, async cancellation and failure controls with
isolated preferences (`CapturePortrait*`, `CaptureDensityTests`,
`CaptureFrameGeometryTests`, `CaptureSharpnessTests`). A missing desktop image
remains a visible error;
tests must not simulate permission success to bypass that path.

[Capture motion](capture-motion.md) owns preview transitions and focus return;
[capture destinations](capture-destinations.md) owns output attribution.
