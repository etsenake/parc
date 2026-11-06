# Portrait controls and rendering

CAP19 completes the Portrait controls, backing-density, color, watermark and
live desktop-background implementation. The user's unified post-capture editor
remains intentional: Portion, Visible Area and Full Page share the same existing
PNG, frame editor and output transactions. Apply and Cancel return to that
preview; changing a frame never captures the page again.

## Retained reference

`4e452201e483b5480c0403a9ef8566e10515cdcb78828622ff9032b202e29547`.
The components/type/cross-reference/annotated-function helpers answered this
assignment; no new heavy REA job or second-version investigation was needed.

outside padding and eight-point vertical spacing. Its primary action has the
Return equivalent and the original skeuomorphic primary-button style.
the color slider and distinct Website Color and Desktop Wallpaper buttons. The
Website button uses the actual page tint, with a tertiary fallback; Desktop uses
its actual wallpaper thumbnail. Both are independent choices, not a segmented
aspect ratio inside a 140×96 thumbnail, 2.5-point inner corners/padding,
five-point outer corners, white at 0.4 and black shadow at 0.15. These preview
constants are separate from the exported frame.

24-point white knob, 152-point travel and eight-point end padding. Its model
the main queue by 0.05 seconds. `WindowScreenshotWatermarkToggle` stores the
replaced by the approved Parc P. Parc uses native AppKit buttons, focus rings,
tracking and a popover-material card within the capture owner. The post-capture
preview shows the actual composed output, preserving varying region/full-page
corners, white at 0.4, black shadow at 0.15) with the 32-point SkeuPrimaryButtonStyle
control, 152-point color slider and website/desktop buttons. Apply Frame remains
the unified-flow label; Escape still dismisses without a visible Cancel control.
Controls are labeled, show selected/disabled states,
retain native keyboard actions and expose desktop errors without fake pixels.

uses `min(1, 2160 / width, 2160 / height)`, rounds the scaled dimensions upward,
adds 384 points and creates a deferred `imageWithSize:flipped:drawingHandler:`.
space. The original lazy image can be rasterized at a destination's density;
it does not establish one universal output pixel size. Parc resolves that
ambiguity explicitly: it retains the original capture window's backing factor,
composes in logical points, and exports at that same density. A 2× capture has
2× frame/radii/shadow pixels and PNG density 144 DPI; the content is never
scaled up before upward integral rounding. The 2160-point source bound and
384-point canvas remain unchanged. This fixed-density policy makes preview,
Copy, Save, Library, Easel and Messages agree. Output composition retains the
source RGB profile (sRGB fallback for unsupported non-RGB sources) and converts
drawing colors through Core Graphics instead of discarding the PNG profile.
The actual original PNG stays byte-identical when the frame is removed.

footprint. Parc applies that calculation to the actual composed desktop below
watermark resource is bundled. The final bitmap and thumbnail share that policy.

## Live desktop and lifetime

non-Dock window, reads its bounds/ID, captures only that window with
`CGWindowListCreateImage`, and constructs NSImage with the window's logical
bounds. It reads visible desktop pixels, not the wallpaper file. The model
retains a wallpaper preview; the compositor invokes the helper when rendering.

Parc's `PortraitDesktopSnapshot` preserves that desktop-window boundary. It
preflights the actual screen-capture permission without requesting or bypassing
it. It requires a wallpaper candidate at or below the system desktop-window level whose bounds exactly match the original
Dock producer remains supported; current macOS WindowManager's `Wallpaper`
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

The production compositor and CapturedImage component checks cover original and
cropped PNG preservation, repeated reversible frames, tall-image restoration,
2× source pixels and PNG density, source Display P3 profile/conversion,
watermark threshold/opacity and bottom-footprint sampling, invalid resource and
desktop failures, same-display wallpaper candidate filtering, native control
callbacks with an isolated defaults suite, cancellation and error sizing.
Nested AppKit light/dark drawing caught an existing graphics-context stack bug:
rendering now restores the exact prior context explicitly. Inert preview captures
include source pixels, frame and watermark in both appearances.

The real desktop-only provider was exercised with existing permission: the
system WindowManager wallpaper window matched 1470×956 logical points and
returned 2940×1912 sRGB pixels. No page or full-display screenshot was taken.
This is native provider evidence, not a functional browser capture, screenshot
permission-bypass claim, or acceptance of every wallpaper/display configuration.
The unified entry/lease, overlay geometry, output destinations, richer editor
and family-wide motion/focus remain with their respective owners. CAP19 changes
no engine overlay and requires no Chromium rebuild.

The full intended diff received fresh independent code review. Its saved-Desktop
failure finding is fixed with a throwing-provider regression check (not simulated
permission success). Finished whole-module SIL passes in 31 seconds with zero
diagnostics, followed by source-identical integration of reviewed CAP20/CAP23.
The original density/compositor files and the bounded controller delta retain
exact-source clearance. Receipts and source hashes are retained under
`work/capture-coordination/cap19` and `work/claude-split-checks/cap19-review-fix`.

CAP24 applies the separately recovered outer spring to the owned native preview
bitmap transition; [capture motion](capture-motion.md) records its native
rendering adaptation, interruption/Reduce Motion and focus boundaries.
