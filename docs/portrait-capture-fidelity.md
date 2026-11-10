# Portrait controls and rendering

Portion, Visible Area and Full Page share one post-capture editor and output
transaction. Apply and Cancel return to the same preview. Changing a frame never
recaptures the page; removing it restores the original PNG byte for byte.

## Controls and image output

The frame card has 10-point outside padding and 8-point vertical spacing. Its
primary Apply Frame action responds to Return; Escape dismisses. A 140 × 96
preview preserves the output's aspect ratio with 2.5-point inner padding/corners
and 5-point outer corners. The watermark control sits at bottom-leading with
4-point padding. Website Color and Desktop Wallpaper are independent choices
beside a 12-point color track with a 24-point white knob, 152-point travel and
8-point end padding. Latest color changes are throttled at 50 ms.

Composition uses logical points: the source is bounded by
`min(1, 2160 / width, 2160 / height)`, rounded upward, and the canvas adds
384 points. Export retains the capture window's backing factor: a 2× capture
has 2× radii/shadow/frame pixels and 144-DPI PNG metadata. Source content is
not enlarged before integral rounding. Preview and every destination use the
same result and source RGB profile; unsupported non-RGB sources use sRGB.

The Parc watermark chooses black at 0.45 or white at 0.75 around a 0.75
brightness threshold using sRGB coefficients 0.299, 0.587 and 0.114. Desktop
backgrounds are sampled beneath the actual mark footprint. Thumbnail and final
bitmap follow the same policy.

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
Desktop preferences wait for the actual image; failure preserves a blank
preview/error and blocks Apply across other refreshes until the user explicitly
chooses Website or the color slider. Denied, absent or failed desktop
capture leaves a descriptive error/help and usable Website/Color choices;
missing desktop pixels never silently render a different background.

## Checks and boundaries

The compositor/CapturedImage checks cover original/cropped PNG preservation,
reversible framing, tall images, 2× density, Display P3 conversion, watermark
thresholds, desktop candidate filtering, async cancellation and failure controls
with isolated preferences. A missing desktop image remains a visible error;
tests must not simulate permission success to bypass that path.

These component checks do not prove behavior on every wallpaper/display or
browser capture path. Current no-app/no-screenshot rules apply to future checks.
[Capture motion](capture-motion.md) owns preview transitions and focus return;
[capture destinations](capture-destinations.md) owns output attribution.
