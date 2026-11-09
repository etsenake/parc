# First-launch implementation

The application now owns a separate welcome/setup window before creating any
browser window. The independent engine starts normally, but all browser entry
points wait for setup: initial launch, File/New Window, Dock reopen, incoming
URLs, singleton relaunch, native popup/window requests and download parent
creation. Deferred navigation is consumed after the final browser reveal.

`OnboardingWindow` owns presentation, cancellable welcome deadlines, native
SwiftUI logo/headline/button animation, its desktop backdrop and `AVAudioPlayer`.
One SwiftUI host stays alive across the three welcome reducer phases, so a phase
change does not reset or truncate the animation. The backdrop is an owned child
behind the setup window; it neither creates a browser nor enters a macOS
fullscreen Space. Closing, replaying or enabling Reduce Motion cancels its
deadlines, removes its layer animations and detaches the child. Leaving welcome
cancels it, and cancels only a dim still waiting for the main screen. The
welcome's logo, headline and arrow are built from the second phase (3.3 s), and
is browser/HTML bookmark import, favorite choices, the shared theme editor and
Space naming, conditional ad blockers, default-browser selection, then the
finished card; see [the November 9 comparison](#november-9-arc-comparison). Direct browser import uses the original
setup window/Space/Profile, genuine native source readers and bookmark hierarchy
selection. Its shared presenter is embedded in the setup content, rather than
opening a second import window. The explicit Import action uses the already
captured setup destination; accepted imports persist separately before setup completion. See
[browser import ownership](browser-import.md). The final review creates the browser only after
`BrowserStore.completeOnboarding` saves the selected setup and completion marker
in one atomic session write. A failed write restores the previous in-memory
state. Repeated completion does not duplicate favorites/bookmarks. An initial
browser-creation failure keeps setup visible with an error and a retry.

`onboarding.json` is a profile-directory draft, written atomically with private
file permissions. Setup resumes at its saved stage after closing or relaunching;
an interrupted welcome replays from its beginning. Closing setup stops music
and cancels scheduled state changes;
it never sets completion. Dock reopen presents setup again. A completed session
bypasses onboarding, and the successful reveal removes the draft. Corrupt drafts
offer an explicit restart of setup, preserving the browser session.

Music starts only with the welcome sequence, at volume 0.3, with zero loops.
The same player remains owned while welcome advances into setup, allowing the
single cue to finish naturally. Leaving a welcome phase, moving between setup
stages or changing application focus does not restart or truncate it. Closing
setup, completing it or terminating the application stops and releases the
player. A new replay started from Settings creates its own player from the beginning.
Resuming a saved setup stage does not start another cue. The system's output
volume and mute remain authoritative. The bundled audio is resolved solely from

## General → Replay onboarding

General settings includes **Replay onboarding**, an explicit requested Parc
addition. It dispatches to the application delegate and creates the same
`OnboardingWindow` owner in `.replay(spaceID:)` mode. Every new replay starts
at `introAnimation`, including the P animation, desktop backdrop, bundled
music, typography/artwork, welcome motion and all current local setup stages.
A second Settings request while the flow is already open resumes that owner.
Settings → General is the only replay entry point; setup and welcome contain
no replay shortcut. The application action requires the original Settings
controller and Space. The former in-flow button and its restart handler are removed.

**November 2 (Josh): replay is the full onboarding and really applies.**
Replay owns an in-memory draft seeded from the originating Settings Space's
name, theme and the Profile's existing Favorites. It never calls the initial
session save, never loads, writes or removes `onboarding.json`, and never
touches the completion flag. Every stage behaves as it does on first launch:
direct browser import and the bookmark-file chooser target the originating
Space/Profile (an embedded import commits when its Import action runs, as on
first launch), the default-browser step requests the genuine macOS handler
change, the theme editor's light/dark control changes the app appearance, the
ready card offers Randomize, and an accepted iCloud Passwords extension
installs after Finish.

The chosen theme previews live on the originating Space through
`BrowserStore.previewSpaceTheme`: the live model carries the preview, so every
browser window showing that Space repaints while the theme is picked, while the
store records the saved theme and every session write (debounced, explicit or
settings commit) stores that saved theme instead. A crash during replay
therefore leaves the saved theme on disk. Another editor's theme save or undo
for that Space, or any change that moves it off the previewed theme, persists
normally and ends the preview; an import destination created from the Space
copies its saved theme. A continuous drag publishes the preview to the store at
most every 50 ms, with no split-layout reconcile or session save; the setup
card follows every frame. Light/dark works the same way: replay shows its
choice with `AppAppearance.preview` without writing `parc.appAppearance.v1`,
so a crash keeps the saved appearance, and Finish saves the choice only if it
is still the one showing. Finish calls
`BrowserStore.applyOnboardingReplay`, which shares first launch's commit
(`commitOnboardingSetup`) in one atomic session write that rolls back on
failure and turns the preview into the saved theme. It applies only what replay
changed from the name and saved theme it started with (both kept in the draft),
so a rename or theme save made elsewhere during replay survives when replay
left that choice alone, and keeping the suggested name leaves a placeholder
title unfrozen. It adds newly chosen Favorites to that Profile and the bookmark
file's links as pinned tabs in that Space, skipping ones that already exist.
Favorites compare with the saved-tab comparison (`SavedTabURLComparison`:
case, `http`/`https`, a leading `www.`, a trailing slash, ordinary fragments
and empty or `utm_` query items don't count), and the grid shows an existing
Favorite spelled that way as selected. Pinned bookmark links compare by exact
URL, so links differing only by fragment or query both land, on first launch
and in replay. Archived Favorites and pinned tabs don't count as existing. A
Space created from sidebar items during a replay preview copies the source
Space's saved theme, as import destinations do. It leaves the active Space, other Spaces, existing tabs, settings, the
completion flag and the first-setup auto-archive education gate unchanged, and
creates no first-launch session state. Because replay never removes tabs, a
Favorite the Profile already has stays selected (clicking it beeps). Retrying
Finish after a browser-return failure does not apply the choices again.

Closing or cancelling replay early, or quitting during it, applies nothing from
the draft: `endSpaceThemePreview` shows the saved theme again (unless another
editor has replaced the preview) and `AppAppearance.endPreview` shows the saved
light/dark choice again (unless a choice made elsewhere has replaced replay's).
Actions that take effect when performed stay, exactly as on first launch: a
completed browser import, a default-browser change macOS confirmed and a
Randomize of the Parc card. The normal browser remains alive with its tabs, Spaces, native pages
and saved settings; ordinary background browser activity continues. Setup
progress reads “Replay · n of N” and the final action is **Finish replay**.

A Safari Full Disk Access restart during replay saves the replay draft,
including its light/dark preview, to `onboarding-replay.json` (never
`onboarding.json`) and records a non-onboarding restart intent marked
`replay`, because completed setup has no onboarding gate after relaunch. Quit
ends both previews as usual. On relaunch only a replay intent consumes that
draft, once and for its own Space/Profile, and reopens replay at the import
with every pending choice; the theme and light/dark previews are reapplied.
Without a matching draft the import resumes in the ordinary import window. The
saved draft is removed when the restart fails or is cancelled, when any other
import restart is requested, when Parc quits without an armed replay restart,
when a dropped intent or launch has no replay intent, and when a new replay
starts from Settings. Closing replay's import cancels only a restart replay
itself requested, never one owned by a File → Import window.

The delegate closes the originating Settings window, keeps the existing browser
windows owned, and presents the full production welcome above them. Completion
returns to the original browser if it still exists after closing the welcome
controller; cancellation returns immediately. If that browser has closed, another
ready browser is used, or an ordinary browser window is created from the
existing session. Browser-creation failure during completion leaves replay
open for retry. Window closure, application termination and a new introduction
all use the existing music/backdrop/animation cancellation paths.

URLs and singleton relaunch destinations received during replay are queued by
the existing onboarding gate and delivered after completion or cancellation.
Returning from replay does not repeat the original launch destination or
install a second set of activity/archive timers. The production initial-launch
path retains its durable draft and one atomic setup commit. This setting and
claimed.

## Reference and adaptation

`4e452201e483b5480c0403a9ef8566e10515cdcb78828622ff9032b202e29547`.
retained version. Static analysis is evidence about source mechanisms, not a
claim that the running onboarding was observed.

  `ev_ed411430309d48fa119276f7217742079825cfcc1bea13ac19674a7fcaad0c80`:
  introAnimation → sellIntro after 3.3 seconds; sellIntro → sellCompleted after
  6.5 seconds. Next advances early; reset restarts the introduction.
  `ev_0aaf6db4b76fb2040e4808f459279f48e00fab74a99dcac6bb5e76344ede3176`:
  retained AVAudioPlayer, welcome-only start, `intro-music.mp3`, volume 0.3, play.
  No loop or fade request appears in that bounded function. Its caller is
  field accesses; it did not find a welcome-stage stop or focus-dependent mute
  in this owner. This supports keeping one cue across the local setup flow;
  it does not establish every system audio-interruption or mute policy.
- The UnboxingManager owns a separately retained UnboxingWindowController,
  window. Its close branch sets `isClosingManually`, calls controller `close`
  branch has no custom alpha animation. It does not establish the ordering of
  the account-dependent parent completion and browser presentation. The state
  model also distinguishes windowClosed and onPressCmdW.
- Follow-up LLVM instructions, cross-checked against retained Swift field
  opacity 0, blur 25, scale 0.5, offset 250, and spring response 1.25 with damping
  spring and sets opacity −1, blur 25, scale 0.5, offset −350. SwiftUI clamps
  opacity when rendering. Parc preserves these values and uses its approved
  1.170.0's AuthFeature bundle reports WelcomeLogo's intrinsic size as 120 ×
  101 points, with PDF and 1×/2× bitmap representations. Parc fits its approved
  borderless P mark proportionally within that measured slot. The mark is derived
  directly from the approved Original pixels; see [UI marks](app-icon-marks.md).
  The P shape and
  the continuity of that asset size from the retained 1.122 binary to installed
  1.170 resources are explicitly distinct from recovered binary facts.

The account/cloud and AI exclusions require a local flow after welcome. Its
setup copy, final review, resumable draft and explicit replay are Parc behavior.
The existing native theme editor and real local import/storage remain connected.
The final handoff prepares the real browser without showing or activating it,
closes the onboarding controller, and then presents the destination browser.
It uses the recovered direct controller-close behavior without an added alpha
fade. The account-free parent-to-browser ordering is a Parc adaptation; the
excluded account-dependent parent's complete order remains unattributed. The
opening desktop dimmer is a separate welcome-only owner. The headline uses bundled Marlin Soft SQ
ExtraBold at 65 points, white, with −3 character spacing. Character travel uses
native font metrics for the recovered character-height term. The welcome uses
the recovered window sizing rule and clear full-content surface. The existing
replay/error controls remain local adaptations. The recovered setup card and
persistent background now replace the former compact setup window below.

Reduce Motion presents the headline and Continue immediately, skips the desktop
backdrop and settles any running welcome motion when the preference changes.
Parc exposes the headline once as an accessibility element and hides decorative
artwork. These are local accessibility adaptations. A focused reference trace
complete welcome policy or VoiceOver focus behavior.

## Recovered welcome choreography

Focused LLVM decoding with retained Swift field metadata, async continuation
captures, dyld bindings and constant values resolves the formerly unattributed
overlay sequence. This supplements the retained REA fullscreen evidence
`ev_cca64015252025cc2ce684bce1e1256eaa82f974087e260887e586ea015cb683`.
The raw-slice REA follow-up `ev_5bebef7ecc23185ed84647d15ae0cb2a850916cfeefce4811cf74e1e2ca6230f`
confirms the entry instruction range only: its external calls are unbound and
its decompiler truncates control flow, so its pseudocode is not used to infer
the sequence. The following conclusions use the full-image instruction/capture
trace instead.

  screen, then creates a screen-sized child with raw style mask 32768. The
  `addChildWindow:ordered:` argument is −1, meaning **below** the welcome window.
  Its layer is black with alpha 0.85, entering from opacity 0 to 1 with a
  1.5-second ease-in/ease-out animation.
  gradient starting below the screen. Its color is `#3139FB`, recovered from
  upward by its height over 0.4 seconds and fades opacity 1 to 0 over 0.6
  seconds, both ease-in/ease-out.
  child frame when the parent changes screens. Parc additionally makes the
  child noninteractive and explicitly cancels every pending cue on interruption.
  Its AnimatedText character path uses initial opacity 0, blur 30 and vertical
  offset `75 + character height`, then animates to opacity 1, blur/offset 0
  with the 1.25/0.9 spring. Delays are 0.03 seconds per character index and
  0.65 seconds for the period. The text has size 65 and tracking −3.
  The button begins at opacity 0, vertical offset 125 and blur 30, then uses
  the same spring to reach opacity 1, offset/blur 0. Its action path
  pending action when the view leaves and prevents duplicate presses.

## Welcome typography, window and artwork

Focused full-image LLVM decoding of the same retained 1.122 executable, with
Swift type references, field metadata and dyld bindings, establishes the
following. These are static findings, supplementing the retained REA evidence
above; the installed 1.170 resources provide the bundled asset bytes.

  before `NSFont(name:size:)`. The welcome sets 65 points, tracking −3 and white
  for the process and retains a logged system fallback if the resource fails.
  screen width exceeds 1280 **or** height exceeds 800; otherwise it subtracts
  72 points from both screen dimensions. The style is `0x8007`: titled,
  closable, miniaturizable and full-size content, without resize. The initial
  welcome is transparent, nonopaque, immovable and shadowless, with window
  tabbing disabled. Parc additionally clamps to the visible work area on
  unusual displays and centers when the welcome is replayed. Setup retains that
  same window size. This does not enter a separate macOS fullscreen Space.
  Its video surface is square, 100 points wider than the welcome window,
  music remains separately owned by the welcome controller.
  references establish two layers: background video with blur 75 and an
  opacity state; then a group of orb video (blur 30, opacity and scale) plus
  grain. The group mask combines a black-to-clear radial gradient with blur
  20 and the `animatingOrbBlob1` image at 300×300, scaled/rotated and blurred
  3.75 seconds for 1 second with ease-in-out: orb scale 8, opacity 0, mask
  radius 2000 and blob scale 30. These cues share the welcome host's lifetime.
  animation lasting **0.175 seconds for the whole four-frame cycle**, repeating
  indefinitely. Reduce Motion uses static `grain-1`. Parc owns the decoded
  frames only while the welcome is presented and removes every layer animation
  and playback item when that view is dismantled.

All font, grain, mask and video resources are included in `Resources/Onboarding`;
installation, decoder process, browser view or engine API is needed. The
630-pixel raster mask is an explicit representation of the catalog's vector
asset, displayed at 300 points before its recovered blur. Bundled first-frame
video posters avoid synchronous decoding on the UI thread and provide a stable
Reduce Motion/decoder fallback. Their attachment-time availability and
settled Reduce Motion composition are Parc adaptations. The decoder-ready
opacity handoff, including the recovered never-positive duration clamp, is
described below. Artwork is hidden from accessibility, and playback is muted
independently of the existing music owner.

## Welcome forward control and video readiness

`ForwardButton<EmptyView>` inside opacity/offset/blur/animation modifiers.
corner radius 8 and horizontal padding 24. The knockout uses destination-out
that arrow-only composition, with the accessibility label **Get started**.

1.02 on hover and 0.98 while pressed, around its center, with spring response
0.3, damping fraction 0.45 and zero blend duration. Disabled controls stay at
disables the invisible or advancing control for keyboard/accessibility input,
keeps the duplicate-action guard, and omits the interaction spring under Reduce
Motion. Those guards and the accessible label are explicit local adaptations.

videoPlayer / videoPlayerLayer / playerLooper / cancelables / assetQueue)
receives a first frame and applies `imageOpacity` from 0 to 1 over 0.5 seconds
payload is false, that function returns without changing layers. When true, it
reads `imageLayer.presentationLayer.opacity`. A nil presentation, opacity ≥ 1
video opacity animation from the presentation value to 1, fillMode forwards,
not removed on completion, no autoreverse, repeatCount 0, ease-in/ease-out,
`beginTime = CACurrentMediaTime()`, added with a nil key, then removes the
repeatCount is infinity when its flag is set and autoreverse is the other
argument; the rotation call passes repeat and not autoreverse.

`fsub` (beginTime − now), `fadd` 0.5, `movi d1, #0`, then
`fcsel d0, d1, d0, gt`: `min(imageBeginTime + 0.5 - now, 0)`. That value is
never positive, so the
recovered video animation is not a remaining-duration fade. Parc applies
`max(recovered, 0)` before `setDuration:` because Core Animation duration is
nonnegative; both the recovered min and that CA clamp yield duration 0. The
previous Parc choice to continue a positive remaining poster fade onto the
video is withdrawn. The bundled first-frame posters, live Reduce Motion
re-attachment of a removed poster, and reversing the handoff if the decoder
drops readiness remain Parc adaptations. Detach, Reduce Motion and
dismantling pause playback and remove both opacity and rotation animations;
dismantling also invalidates the readiness observer and removes player items.
Muted video layers remain separate from the single-play welcome music owner.
The bounded audio function still establishes volume 0.3 and play, with no new
focus-dependent or onboarding-specific mute policy recovered.

The bounded AuthFeature selector search found no direct haptic call, and the
three inspected shared haptic wrappers have no attributed AuthFeature callers.
This does not prove that every possible indirect haptic path is absent. No
welcome haptic cue is synthesized from those unrelated wrappers. Reference-wide
focus, VoiceOver and audio/mute policy are not inferred from the narrower
owners described here. The video/poster handoff comparison itself is the

## Closing and interrupted quit

First launch constructs its browser while the welcome window still owns
presentation. The factory's `showImmediately` argument controls only shell
visibility; `renderInitialSelection` still initializes the real page/session.
Ordinary and engine-created window entry points retain their existing behavior.
After setup saves and destination preparation succeeds, onboarding stops its
music, cancels the backdrop, closes its retained window, and synchronously calls
the parent. The parent then activates the prepared browser and delivers queued
requests. A preparation failure leaves setup visible and retryable.

Replay uses the same handoff and returns to the original surviving browser or an
eligible existing destination; it creates a browser only when none remains.
Replay's draft stays in memory and applies on Finish. Cancel restores its
theme preview and returns immediately to browsing.
Pending termination consent retains the current welcome host and audio player.
If an existing replay page declines Quit, the parent resumes the retained window
without calling the initial presentation path, rebuilding the host, replaying
music or resetting the welcome stage. Approved shutdown tears down that owner.
This is the Parc adaptation for its aggregate native termination-consent API;
inferred from the bounded music owner.


## Persistent setup presentation

`OnboardingWindow` now retains one background host through welcome and setup.
its left column is 357 points including 50-point padding, with 20-point content
corner20 and black0.25 shadow, radius17 and y14. These measurements replace the
previous centered compact dialog, preserving real drafts, import and completion.

reads palette offset0xb0. The independently attributed CSS exporter
`backgroundExtra`. Parc uses its existing theme palette for that same color;
unthemed CardBackground falls back to the installed1.170 AuthFeature colors.
Theme preview and commit update the original card without replacing its controls
or painting the whole welcome window with a Space gradient.

strokes two continuous corner-20 rounded rectangles at 1 point with miter 10:
an outer `RoundedRectangle._Inset` of −1, then the SwiftUI half-width stroke
CardInnerBorder and CardOuterBorder. Unthemed AuthFeature values: inner
white/0 light and white/0.2 dark; outer black/0 light and black/0.61 dark.
specks, alpha mean 16.5/255, clipped at 41, drawn as-is. Parc doesn't bundle
it; at Josh's direction (November 2) the card draws the chosen Space theme's
texture exactly as the sidebar's theme renderer does, through the same
`ThemeTextures` file, `SpaceTheme.textureStrength(isActive:)` (grain dial ×
the texture's maximum, a quarter while `ThemeWindowActivity` says the window
is inactive) and 100-point `ThemeTexturePitch`, bilinear like the renderer's
sampler, with multiply, which on the opaque fill is the renderer's
`themeComposite`; changes apply without implicit animation. No theme, a theme
card would still show its faint fixed grain then. Tiles start at the card's
corner rather than the window's origin. Before this the card always tiled
`ThemeTextures/grain.png`, whatever texture was chosen, at full strength and
220-point pitch with multiply/screen, several times stronger than the sidebar. Grain and inner stroke clip to the continuous 20-point
card; the outer stroke and black 0.25/r17/y14 shadow stay unclipped.
not larger. Parc's small-screen card fit still scales the original 967×548
bounds inside 24-point horizontal and 48-point vertical margins so grain,
borders and controls stay in one coordinate space. CALayer borders paint inset
from their bounds, so the outer layer is expanded 1pt (`cornerRadius = 21`)
and its 1pt continuous border occupies −1…0.

OB16 maps that overlay in `OnboardingSetupCard` on top of the published
grain/outer-stroke chrome (`5397b14e`). CardBackground / CardInnerBorder /
CardOuterBorder are named `NSColor` once-inits (recovered names; unthemed
catalog values, no AuthFeature bundle). Grain is the Space theme's texture,
drawn by the sidebar's rules (above). The inner stroke is a
1-point continuous CALayer border on the full card bounds, composited above
the content column so full-bleed steps cannot cover it: that inside paint has
centerline 0.5 and occupies 0…1, matching the SwiftUI 0.5-inset centered
stroke. Recovered `StrokeStyle` lineWidth 1, lineCap butt, lineJoin miter and
miterLimit 10 are set on both stroke layers; visible ink stays the continuous
border so it follows the fill's `cornerCurve` rather than a circular path.
The outer stroke (expanded 1pt, ink −1…0) and black 0.25/r17/y14 shadow stay
unclipped. Grain stays clipped on chrome. Small-screen fit keeps the original 967×548 bounds
inside 24-point horizontal and 48-point vertical margins so grain, strokes and
controls share one coordinate space; ordinary 1280×800 windows keep the
unscaled card. `OnboardingWindow` already applies that frame and
`setBoundsSize` in its existing root layout and was not rewritten.

Isolated AppKit checks cover named once-inits, 220-point grain pitch, inner
centerline above the content column, unclipped outer stroke/shadow, recovered
StrokeStyle, and one-coordinate-space scaling including 1280×800 and
screen−72. Independent review CLEARed this source. A component check is not
a live window screenshot.

REA evidence is `ev_83741a0706f08836a50a42739c693933a04d3d3a6a275eb04e2537af291b803b`
(Unboxing), `ev_351939008cc4c2c8e5033f5b5f7b784eb4252ce8bdc8cd1f04e8d8af36447411`
(Setup), `ev_7bd0efb79c863a382d524417d30e3b1877db5aa78d348db3e8dfa38468a25d54`
(Card), and `ev_b8ca960ece8acd8da8de708aeaf00860665042d19bfdf3c51eeed54c1ae4b5d7`
(editor palette). Raw-slice external calls require the retained full-image
instructions, imports and Swift key-path metadata for attribution; the decompiler
alone does not establish named colors or original Swift source.

The whole first-launch family remains active. Remaining work includes each
account-free step's complete content and controls, precise step and theme
transitions, final reveal, keyboard/accessibility and audio interruption, and
any genuinely recovered haptics. Uniform fitting on small screens and settled
accessibility/resume composition are explicit adaptations. Card overlay
mapping (named once-inits, 220-point grain, inner/outer strokes, one
coordinate space) is in `OnboardingSetupCard`. The isolated AppKit checks cover all five
card layouts, grain/border chrome, coordinate scaling and light/dark optical
updates. A component bitmap established control placement only; it omits
video/SwiftUI compositing and is not a live window screenshot. No browser
functional test ran.


## Setup progression control

The setup footer now uses the same SwiftUI progression style as the welcome
arrow: continuous corner8, height40, disabled opacity0.5, hover scale1.02 and
pressed scale0.98, with response0.3/damping0.45 spring. Reduce Motion settles
these states. The text specialization fills the 257-point instruction column,
with no added arrow or invented font override. It keeps one hosting view through
draft/color updates, rather than drawing a colored native bezel. The native
SwiftUI button retains accessibility and default Return. Disabled, hidden,
non-key or sheet-owned setup cannot advance, nor can marked-text composition.

optional direction nil, knockout foreground and the actual theme getter. Its
label. The builder also applies the recovered0.12-second enabled transition.
REA evidence `ev_48cebc050fc43562531c01241f4ae8e357fc6b40d2d80e90026b2dafdad353a1`
is paired with full-image imports and Swift type/key-path metadata; the raw slice
alone cannot name those Swift types or semantic colors.

bundle resolves them to sRGB(49,57,251)/255 and white in both appearances.

The combined application compiles with warnings as errors. The focused native
card check uses the actual hosted progression control at its production bounds.
These checks do not establish final step choreography, haptics, or complete
onboarding parity; the remaining whole-family work above stays active.

The actual isolated onboarding window was visually inspected in light and dark selected themes: the 257×40 control, semantic fill/text, card typography and live appearance updates are visible. This used a disposable local draft with no engine or imports. The selected-theme editor composition and remaining step presentation still need reference completion; these screenshots are not whole-flow parity evidence. An independent source review found no actionable hidden/default-action or hosting-lifetime issue.


## Optional default-browser step and setup order

`RadioGroupLabel` controls to one pending Boolean: “YES, make Parc default.”
339-point width, 67-point row height and 22-point row spacing, an enabled border,
rounded corners, hover scaling and the current theme's `maxContrastColor`.
The Yes option is preferred; the initial choice is Yes. Selecting a row changes
starts the macOS request through the application-wide default-browser
controller and moves to the finished card at once; onboarding never waits for
the answer or shows its outcome, which only Settings' banner reports. No
advances without a request. Replay makes the same request.

indicator diameter22 with inner fill14, label gap19 and label width250 with
16-point system text. The continuous corner is15, border width1.5, shadow black
at opacity0.05 with radius6 and y5. Unselected borders use PopoverTitle at0.1;
the indicator is white with a black0.25 outline. Selected labels and outlines
PopoverTitle to sRGB(0.094,0.106,0.122) in light mode and white in dark mode.

scale1.04 with spring response0.18, damping0.8 and blend0. The preferred Yes
indicator displays `heart.fill` at25 points when selection changes to Yes;
the heart is present. Parc cancels the reset with its view lifetime, suppresses
motion under Reduce Motion, and exposes each option once as a selected button;
these lifecycle/accessibility safeguards are local adaptations.

REA evidence is `ev_80c1118e631f649d788b0bb95b49dbbb68acadb0c30f7b639604bbd51f083c48`
(label), `ev_8c9db266721fe298d924c57387363baa36c6bc1d215f6b3a50166993a66f4f39`
(button), `ev_98c2ded8d60b1a7bf3f310e94dd6dd1723af195b10fda6eee1303504408b1273`
(row) and `ev_260439940209a7b7e270de288c91031dfffef81e6f2f34010e675b90d60cb445`
(hover). These bounded raw slices require the retained full-image instructions,
Swift metadata, imports and constants for attribution; pseudocode is not the
original Swift source. All addresses use the retained1.122 artifact above;
resource colors were read separately from installed1.170.

`OnboardingDraft.Stage` keeps all existing persisted integer tags. The former
generic introduction card migrates to import; explicit next/previous order
replaces enum arithmetic and appends the default-browser tag without reusing
old values. Existing drafts retain their actual stages and explicit No survives
restart. The implemented account-free sequence is a bounded adaptation of
`.bookmarks`. The conditional ad-blocker step is implemented; remaining
ready/reveal, step motion, and whole-flow keyboard/accessibility work stay
separately open.

## Included setup order and ad-blocker branch

2 `importBookmarks`, 3 `safariPasswordImportOptions`, 4 `importSafariKeychain`,
5 `spaceStyleEditor`, 6 `topApps`, 7 `adBlockers`, 8 `arcMax`, 9 `defaultBrowser`,
preserving the current one. Nested first-launch import already covers tags 0–4
`skip-and-auto-select-onboarding-favorites-enabled` is off, which puts
`topApps` in slot 2, after source choice and Safari access and before the
whole import, slot 6), pending Josh's decision: bookmarks → favorites → theme →
conditional adBlockers → defaultBrowser → ready.

`ImportFeature.AdBlockersSelection` is setup tag 7. NewSetupView's adBlockers
invasive trackers or intrusive pop-ups.” Selection cases are userSelected,
noAdBlock, arcNative, uBlock, keepAll. Copy for noAdBlock is “Don't block ads”
/ “All ad blockers will be removed, I was looking for new socks.”
no native content blocker; `keepAll` is an existing-member path and is omitted
that native identifier:

`cfhdojbkjhnklbpkdaibdccddilifddb`, `aemffjkmgcepimloclpkecifcnipnodh`,
`mlomiejdfkolichcflejclcbmpeaniij`, `pkehgijcmpdhfbdbbnkijodmdjhbjlgp`,
`cjpalhdlnbpafiamejdnhcphjbkeiagm`, `ddkjiahejlhfcafbddmgiahcphecmpfh`,
`bgnkhhnnamicmpeenaelnjfhikgbkllg`, `gighmmpiobklfepjocnamgkkbiglidom`,
`ohahllgiabjaoigichmmfljhkcfikeof`, `lgblnfidahcdcjddiepkckcfdhpknnjh`,
`bkkbcggnhapdmkeljlodobbkopceiche`, `pmekfefnodgilnnjcfkkdjlebokonhpm`,
`gekdekpbfehejjiecgonmgmepbdnaggp`, `ggdpplfehdighdpleoegjefnpefgpgfh`,
`onomjaelhagjjojbkcafidnepbfkpnee`, `ojjjflcdgjegkdcojbahlbgeiinpbfgf`,
`jhkhlgaomejplkanglolfpcmfknnomle`, `gekoepiplklhniacchbbgbhilidiojmb`,
`amgmhmoikcefmalfmbpkpnnpebhmhfnd`.

Parc includes the step only when one of those IDs was actually submitted with a
non-failed first-launch import (or the current draft stage is already
adBlockers). The pending keep/none choice resumes with the draft; Skip leaves
it unchanged. There is no native uninstall/disable API on this path, so none
does not fake-disable imported extensions. Default selection is the first
imported blocker. No extra steps are invented.

SHA256 `4e452201e483b5480c0403a9ef8566e10515cdcb78828622ff9032b202e29547`.
Helpers: `components.py find` UnboxingManager / ImportFeature / NewSetupView;
`arctypes.py` / `arcfn.py` / `arcidx.py` on `arc-1.122.db`. Account, cloud and
AI steps remain excluded.


The production default-browser screen was inspected in an isolated native
onboarding window with a disposable draft and inert import boundary. Both
options expose their native Button roles and selected state; selecting Yes
shows the preferred heart without duplicating it in accessibility. No engine
or macOS handler change ran. Draft migration, explicit No persistence, stage
navigation and atomic completion checks pass; the existing injected controller
passes23 ownership assertions. Independent source review found no actionable
migration, callback-owner or replay issue. The final combined164-source application passes warnings-as-errors typechecking
with zero diagnostics and unchanged inputs. These checks close this step's
implementation; they do not close the remaining onboarding family.

## Inline browser import owner and source rows

The first-launch importer shares the setup window and card. `BrowserImportViewController`
owns actual discovery, original-source selection, native admission, access/password
continuations and bookmark acceptance. The menu's `BrowserImportWindow` wraps that
presenter; setup embeds it. Native consent remains attached to the original window.
First launch's explicit Next action uses its captured Space/Profile without
creating a second destination. Existing cookies remain protected. Real extension
consent, cancellation and committed-category results keep their existing native paths.
HTML selection retains the exact panel, stage, setup window and importer instance;
a late callback cannot modify a later setup step.

`4e452201e483b5480c0403a9ef8566e10515cdcb78828622ff9032b202e29547`,
REA evidence `ev_9148913738d6384f72cacac5347114921314e87085e938a746fe58f97ba84aea`
and `ev_20b5a9b440e8415153a13e2cd0f25f5ea598a31163e38491e4c9e06b31f0749d`
are bounded: the large reducer's pseudocode does not recover its switch; the
retained instructions and decoded dispatch table establish these branches.

`ev_842c7ac7855b80a51d90542d9e2b8f35b73e0b29bbf3ff6fdab8c2409a1ee3c4`)
uses width 278, horizontal inset 24, vertical inset 16 and 0.2-second selection
establish 20-point spacing, 92-point height/image cell, 50-point icon, uppercase
13-point semibold text, −0.02 kerning and #767676 text. The 2-point separator
discovered app bundle identities/icons, with a neutral fallback for extra sources.

The HTML entry, isolated replay and original-destination policy are explicit
local adaptations. Subsequent source-profile, bookmark and Safari-access
composition deliveries are below. Password composition, complete profile optical
treatment and capability-dependent step ordering remain unfinished OB17/OB18 work.

### Inline source profiles

The selected browser now reveals its profiles in the same source card stack;
there is no extra first-launch profile page. One readable profile is selected
automatically, and the radio group appears only when the actual result contains
several profiles. Selecting a browser starts cancellable native discovery, not
import. Next stays disabled until that result and then either opens genuine
Safari access guidance or imports into the original first-launch destination.
The application-menu wizard keeps its separate profile and destination pages.

than one (REA `ev_b1479c10b64b245e79dfa19e57b793a3c0b18d4f73c6f73dee0cdaf108117634`).
one-point outline and horizontal padding12. Its bounded raw-slice REA result
`ev_3bbab512e845770be9aa64e52d9726eed2e8271dd877b61ae081a14decdf0bbd`
uses SHA256 `2ca7060c00e7d3f46d08014742e7bc511e580670eeeb1328cf72630d2b760dfb`;
external calls are attributed with retained full-image instructions, not inferred
14-point vertical padding and separators except after the final option. Shared
indicator sizes. The actual configured checkmark, label and hover behavior are
resolved in the control comparison below; whole-flow focus remains OB33.

Changing browser, Start fresh or accepting an HTML file cancels the old native
lease and invalidates its generation. Stale callbacks cannot restore a discarded
choice. Profile and extension actions validate the original source and profile
objects; import keeps the exact window/Profile and explicit extension consent.
Readable-only Safari continuation remains truthful after a denied permission.
The loading indicator, capability/error messages and extension checkboxes within
this stack are explicit adaptations to independent Chromium discovery/consent;
setup composition remains; bookmark selection is described below.

This delivery passes the combined 166-file Swift whole-module check with warnings
as errors and 97 isolated import coordinator/access/password assertions. The actual
source/profile SwiftUI component was rendered in native hosts and inspected in
light and dark appearances; the first image-renderer attempt omitted the native
scroll view and was discarded as appearance evidence. These checks do not execute
a browser or prove the unfinished full setup sequence. OB17/OB18 remain LEFT.

### Inline bookmark selection

The embedded importer now uses the original list composition: per-source-profile
sections when there are several results, a source-scoped Select All row, circular
selection controls and independent folder-label expansion. A folder circle
selects its subtree, including collapsed descendants; its icon/title expands
without changing selection. Duplicate names/URLs keep their original IDs.
Result-page UUIDs and the original owner/destination are checked on every action.
Acceptance uses the existing atomic store transaction, preserving ancestors of
selected leaves and refusing duplicate or retired-owner admission.

light inside dark setup. Root REA:
`ev_5a18d6ceac489d4dcf87802ab045e346f324940a6b7eed4e2f520d5c3782ad62`.
`ev_a5161ad98448d51037df9a8565e043f821941102d044a85da04ae15b393163fc`)
places level×10 indentation after the selection circle, uses title3, and gives
the virtual root a bold Select All label in the folder-stroke color. Folder
retain selection. The row has bottom padding12; expanded children move from
are `ev_6736cc83b2670ed39e902990fddbb08153a7160fc4925bac7b1106305b465d1b`
and `ev_94b15bf28a7bee64da56170a5c8f6eac233a9a77d30a3d704dbc045e7d2d45ff`.

The label embeds a native `FolderIcon.FolderIconView`, not a disclosure chevron.
`ev_76fcf2c32b20f6c6ca6f24c228abb3ef8473e2c7cbc5d7130ecbf507eb58758e`)
constructs separate back/front paths, scale-rounded stroke width1.25, radius
round(width/7), a quarter-height front inset and 42%/58% tab shoulders. State
`ev_58d46c2278691d406e9339a0f21d53db985b2903f89862ff85c42793a9c2ace4`)
retains both layers, lower-left anchors and perspective −1/350. Expanded state
translates x3, rotates y32°, then pitches the back +28° and front −30°. Its
native transaction enables implicit actions; no custom duration was recovered.
Front/back gradients are black0→15% and black0→36%, with original endpoints,
locations and expansion opacity. Only the collapsed/expanded states used by
this picker are implemented here; unrelated sidebar peek/badge/custom-image
states are outside this component.

`AuthFlowFolderBackgroundFill`, `AuthFlowFolderForegroundFill` and
catalog SHA256 is `db629aa825d036ea9ba674806bf0fdc42363bcdf5bb7d77ca2e05e95287bdd8d`.
Actual AppKit color lookup yields sRGB background(.753,.757,.957),
foreground(.941,.941,.937), stroke(.192,.220,.988), identical in Aqua/Dark Aqua.

Full-image instructions, import bindings and constant tables corroborate the
bounded raw-slice decompilation; unbound pseudocode alone does not identify
AppKit/SwiftUI calls or floating-point rounding. Main artifact identity is the
evidence remains in `work/arc-onboarding-presentation/evidence` outside Git.
Parc adaptations are stable result tokens, explicit accessible action labels,
Reduce Motion settling, error/status messages and the existing 24×16 embedding
insets. Complete keyboard/VoiceOver traversal remains OB33; remaining import
profile optics and Safari access/password composition keep OB18 LEFT.

The increment passes the 169-source Swift whole-module check with warnings as
errors and unchanged inputs, 117 actual coordinator/access/password assertions,
72 import selection/store assertions and five restart-persistence checks. Actual
native hosts were inspected collapsed/expanded and in light/dark appearances;
six layer geometry/state assertions also pass. The first dark render exposed the
missing light-scheme override, which was corrected from the bound original
environment write before the final checks. This is component/source evidence,
not browser testing, full setup acceptance or measured animation equivalence.

### Chrome and other Chromium sources need the same Full Disk Access owner

On current macOS, `~/Library/Application Support/Google/Chrome` exists and
`stat` succeeds on `Local State` and `Default`, but `access(..., R_OK)` and
directory listing return `EPERM` until Full Disk Access is granted. Discovery
used to keep that restricted Default with zero readable categories and only
opened access guidance for Safari, so Chrome showed as having no usable
profile. Restricted results for every source now use the existing Full Disk
Access owner; Chrome may stay open because snapshots retry live WAL copies
and open only an unchanged private copy. A still-changing database is refused
instead of importing a torn snapshot. Restart after Full Disk Access persists
the original source bundle ID so Chrome resumes as Chrome, not Safari.
Identity of the original bundle and profile directory is still required.
Author checks for this increment: 160 isolated import owner/access/password
assertions, 87 selection/store assertions and 6 restart-persistence checks.

### Safari access inside setup

Safari access now remains in the same 967×548 setup card, with the original
heading/description in its left column, the shared Next control, and a passive
System Settings illustration occupying the right column with top48 padding.
The standalone menu's 790×630 navy screen is still used by its own window;
first launch no longer switches into that presentation.

`ev_51727b09e3cf29f7762905262c5c848b5e5a00640321020c79749cd9537fae41`,
`SystemPreferencesVentura`, `Image(nsImage:)`, stretch resizing, top48 padding
and the top-aligned flexible frame. The heading and description producers are

Its import catalog SHA is recorded above; native image export SHA256 is
`0a79c693f38eb4e201124a56ab6e425b57df7e120322360ee83610ec3fbe7453`.
It depicts the Settings sidebar, disabled example permission rows and a dashed
guide from the plus button to an application-path callout. Parc reconstructs
that illustration in native drawing source with its P icon and neutral local
identity. The illustration has one image accessibility description and no
clickable switches. It never represents the machine's actual permission state.
Native symbol substitutions, neutral identity, precise antialiasing and the
callout for the actual installed copy are adaptations, not an exact raster copy.

Open Settings, Show in Finder, guarded Restart and aggregate access/error text
remain real actions of the existing importer. Their supplemental left-column
presentation is an adaptation; the original first-launch permission action
sequence remains part of OB17. Next invokes the same fresh source-readability
check used by Continue without restarting. Repeated card configuration preserves
attached controls and first responder during the one-second poll. Original
destination, cancellation, restart consent/resume and password-file ownership
are unchanged. The password composition below continues that same setup owner.

The 170-source warnings-as-errors whole-module check passes with all 270 inputs
unchanged. Existing isolated coordinator checks pass 117 assertions. The actual
native card is rendered in light, dark, ready and error states; component checks
cover the passive illustration, bounds, enabled actions and first-responder
retention. These checks do not open a browser, change permissions, restart Parc
or import personal data. OB17/OB18 remain LEFT.


### Password import inside setup

First-launch password import now uses the persistent two-column setup card;
its separate navy 580×630 auxiliary container has been removed. The application
menu retains its own existing import window. Both presentations use the same
`BrowserImportCoordinator`, original destination Profile, native CSV session,
stop/result handling and explicit exported-file removal consent.

The body centers ordered `OpenSafariPreferences`, `ClickOnPasswords` and
`UploadPasswords` guidance with a 25-point gap to the click/drop region.
error or success glyph, 28-point semibold symbol and 20-point semibold message.
`ev_e1e0b48671179f045f13cf7ce7e51f5781a55be7e94237a9d6ab2051841d98a3`
and `ev_4c59f3742aee8b5b4f5760a846cb12b1214fbf807b09d444ff35a55406322717`
are bounded raw-body evidence, attributed with full-image instructions, imported
functions and Swift metadata. They are not recovered original source.

non-completed/completed background, border, error, label and symbol to the named
`AuthFlowDropTarget*` resources. The body uses a separate key-symbol foreground
from its text foreground; success changes both the fill and outline. Parc now
recreates those roles, including their distinct light/dark values, from the
newer-resource observation, not a claim that the retained 1.122 catalog was
Parc code. Actual partial/native errors use the error role with Parc's aggregate
result explanation rather than declaring a successful upload.

Parc's native target is a real keyboard-accessible button and file-drop receiver.
Admission is disabled during import/removal; only a confirmed completed native
result produces Success. Partial, cancelled and failed results stay distinct
from success. Supplemental aggregate results scroll without moving the target;
Stop and explicit Trash controls keep their original importer callbacks. Shared
setup progression waits while import/removal is busy; skipping remains available
before import and continuing after the result. No credential values enter Swift.

Current macOS instructions name Apple's Passwords application on macOS15+ and
Safari Settings on older supported versions. This is a platform adaptation,
alongside Parc naming and the existing confirmed-write/consent behavior. The
instruction composition is detailed below; help presentation, state motion,
profile optics and the full conditional order remain open;
this increment does not close OB17/OB18. Evidence and native component captures
are retained in `work/onboarding-password-composition`, outside Git.

The final 174-source warnings-as-errors whole-module typecheck passed with all
274 recorded source/header inputs unchanged. The existing isolated import
coordinator suite passed 117 assertions. The actual native password card passed
19 action/result, disabled-AX, first-responder, retained-view, geometry and menu
preservation assertions and five state captures. The ready/light and completed/dark
captures were visually inspected for the new composition. These checks use no browser or real credential file and do not
establish complete onboarding parity.

### Password instruction composition

The same retained 1.122 image establishes the actual numbered instructions.
number and the existing drop-target background/foreground roles. Its opaque
imported nominal references identify a `ZStack` of `Circle` and `Text`.
The circle is established by that concrete type, not inferred from the frame.

They compose 14-point light narrative with semibold menu names and a native
chevron symbol. The second instruction owns the separate help control;
role, with native link-button and tap-gesture branches. REA records
`ev_354337bc161c3c7dcd670d8ced6d70585e7b118f17c3fcd245d85595cc6407ed`
and `ev_bdb50f1cbcf3ef9dc72241b6fb154520e610885674cbdf9f6f1f1f4c9278d36a`
are corroborated by original whole-image instructions and metadata. The
shared whole-program corpus was still importing during this bounded pass;
the retained evidence is outside Git in `work/onboarding-password-instructions`.

Parc now uses native attributed labels with those roles and one spoken
instruction per row; decorative counters and inline symbols are not duplicate
accessibility controls. The actual help button remains in the keyboard chain,
between the second and third instructions. The final row retains the original
25-point gap before the drop target. AppKit text measurement and symbol baseline
placement implement the recovered composition; exact SwiftUI optical equivalence
is not claimed by the type mapping. Current-system wording remains the explicit
macOS15+ Passwords-app adaptation described above. This does not change importer
state, native file ownership or the separate application-menu presentation.

The actual callback dispatches
`ImportSafariKeychain.Action.howDoIFindSafariKeychainFileTapped`; the subsequent
parent-owner trace and implementation are recorded below. The instructional
image's fixed frame alone was not used to infer a window or sheet. OB17/OB18
remain LEFT.

The final 175-source whole-module typecheck passed with warnings as errors and
275 unchanged source/header inputs. The actual native card passed 27 component
assertions, including row accessibility, help activation/focus, ordering and
the existing import/result states. Light ready and dark completed renders were
visually inspected; the inline symbol follows the current appearance. A separate
source review found no actionable layout, ownership or menu-import regression.
No browser, password unlock or credential import was run.


### Password export help owned by onboarding

`AuthFeature`, whose concrete body contains an
`IfLetStore<ImportSafariKeychain.State, Action, SafariKeychainModal>` inside
present a window for that action. The parent owns the presentation.

continuous rounded rectangle with radius 16, and a black 0.15 shadow of radius
`PopoverBackground` asset. This establishes the enclosing card separately from
supplies the 36-point bold heading, leading inset 85, image top inset 24 and
32×32 close control with an 18-point xmark and trailing inset 24.

REA evidence
`ev_0eadeda79ff9e3f196d896578b0c25c572f40a5d9f841f0208a3ebd7ff014e6f`
(parent),
`ev_ce12a4631a4383a46e49733dcd900c6eca6c4dbcef5f46738b2236f802964810`
(content) and
`ev_b1808990c1a7aaa530cd0d6f912b86ed94f6be0828549328c97933c92c4ed0e0`
(child reducer) is retained outside Git in the onboarding reference cohort.
The bounded decompilation is corroborated by original whole-image instructions,
resolved Swift metadata and imported framework calls; raw-range external globals
alone do not establish those types. The shared whole-program corpus was still
importing during this pass.

`OnboardingPasswordHelp` now lives above the existing setup card in its original
window. Closing it preserves the importer and selected source. Visible help
captures pointer input and focus, hides the covered setup card from accessibility,
and prevents covered Back/Next/Skip actions. Escape, backdrop and close dismiss;
owner cancellation or departure retires the overlay. Focus returns only to the
surviving original control in the same key window. Hidden help passes pointer
input through. Reduce Motion removes decorative transitions. The separate
application-menu importer retains its existing help presentation.

1.170.0 (89123), `ARC_ImportFeature.bundle`'s
`SafariKeychainImportVentura`, for the macOS13/14 path. Exported PNG SHA256:
light `1432f7bb835ebbceb26c2aa38d67a8bcebda95a3c21a262db060a5ce10a70933`;
dark `2fa853a1d2810d8e824a23d386376abce6403d14de8b7fc7bbfcb7c05eee73b0`.
The same installed reference supplies the `PopoverBackground` light/dark P3
color values. Asset extraction records live in `work/onboarding-password-help`;

Explicit adaptations: macOS15+ uses current Apple Passwords export instructions
inside this owner instead of presenting the obsolete Safari settings diagram;
small windows scale the card to fit with 24-point margins. The plain close-button
Its exact hover/press optics, remaining import profile treatment, upload-state
motion and full conditional setup sequence keep OB18/OB17 LEFT. This increment
does not establish whole-onboarding visual, VoiceOver or browser acceptance.

The 177-source whole-module Swift check passed with warnings as errors, zero
diagnostics and 277 unchanged source/header inputs. A separate source review
found no actionable importer ownership, cancellation, covered-navigation or
focus-restoration issue. The actual native overlay passed 14 assertions covering
same-window ownership, inactive/active hit testing, forward/reverse Tab containment,
close, focus return, idempotence, Escape and owner detachment; light/dark renders
were inspected. The close button was present in the native accessibility tree
and activated through the computer-use tool. Earlier in-process AX enumeration
and synthetic mouse delivery did not establish that boundary; they caused no
production workaround. This is not a full VoiceOver check. Checks and captures
remain in `work/onboarding-password-help`; no browser or credential import ran.
Peer changes through `d8618a0` affect separate Favorite/Today creation paths;
the reconciled onboarding inputs are unchanged from the successful full check.

### Import profile and help controls

The profile rows now use the actual configured selected checkmark rather than
an unconfigured radio dot: 16-point filled selection circle, white 8-point bold
checkmark, 13-point medium label, tail truncation, full-title help and an
18-point trailing label inset. The white profile-container fill applies in light
appearance only. Selection still submits the original single source descriptor.

that configuration is present; the 10-point inner dot belongs to the alternate
configuration and was incorrectly used previously. The precise label consumer
`ImportFeature.ProfilePickerOption`, whose resilient conformance at
provides #767676 ink and conditional white fill. REA
`ev_ef5e179ed433ae5b190c75b454593104e26dd401664ee6e4ea216be0044654d2`
(label slice SHA256 `f36dd4982f5faefcfac8779c878a7e6a3b6b38987104d1de309fe6f7dae8a4d9`)
and `ev_16a485e762f8a087676fd08192d613e40219ed83b003e7311bb29b5311d031f3`
(radio slice SHA256 `950ae6c032bd68da5d5a1a798cfffa3f2cb6069cf055dafb61a21d5851cad160`)
are corroborated by full-image instructions and metadata.

The initial interpretation that these profile rows needed the shared radio's
hover/selection spring was incorrect. This caller disables `ScaleHoverEffect`
preferred-heart state, which this caller does not display. The configured
checkmark retains the indicator's scale transition without adding a profile
hover enlargement or an invented spring. REA
`ev_635ada21d9d78ffd2096a1b3cce612a7107736bfaba8d6d6ca570fce56d7bf40`
and `ev_07e7377298b252f3b1eb75fc10094a5629ca778fce4a25001938835cc472ce50`
resolve those binding/state paths; the shared control is not sufficient by
itself to infer which options this screen enables.

Help's close button now uses 18-point bold xmark and the original 5-point rounded
hover/pressed surface inside its existing 32-point frame. The recovered
uses GrayA4 when hovered and GrayA5 when pressed, with no scale animation.
REA `ev_ac12f8b35cd2ab4231f07de6adce48efaeae1d730e151fe15809d27fac0a87d7`
uses slice SHA256 `bc4c0710062988601070fc19e550ac38d78adb1785bb528a9bc79677b30558c4`.
white alpha .077/.103 in dark appearance. These constants are in Parc source;

The actual native source/profile and help components were captured in light and
dark appearances in `work/onboarding-import-controls`; the profile geometry,
checkmark, medium text, truncation and light-only container were inspected.
The dark cached-view capture omitted the browser application image; that capture
is not evidence of icon fidelity. These appearance checks do not establish
full setup acceptance. The remaining OB18 work is the complete conditional
import presentation/action sequence and the upload-state transaction attribution;
whole-flow transitions/focus retain their separate OB32/OB33 requirements.

The 178-source whole-module check passed with warnings as errors, zero
diagnostics and 278 unchanged source/header inputs (139.20 seconds, base
`37fb76b`). The subsequent `37c68f9` reconciliation changes only Downloads
source/tests and its ledger; the checked onboarding inputs are unchanged.
The native appearance executable also compiled with warnings as errors. No
browser or credential import ran. Commands, input hashes and results are in
`work/onboarding-import-controls`; the disposable appearance executable was
removed after capture.

### Import progression inside setup

Setup now presents genuine bookmark results before the optional Safari password
step. Accepting the selected tree saves it to the captured first Profile/Space,
then offers exported passwords. Skipping passwords finishes this import without
reopening or duplicating accepted bookmarks. Empty native bookmark results omit
the selection screen. Stop suppresses a later password offer even when native
completion wins the cancellation race; returned bookmarks remain selectable.
The dedicated menu wizard retains its separate order and destination choice.
Setup's outer progression button keeps the recovered `Next` label instead of
inheriting `Add to Parc`, `Skip Passwords` or `Done` from that menu presentation.

step list with `importBookmarks` (tag2) before `safariPasswordImportOptions`
steps while preserving the current one. REA
`ev_c02a0882336d1a42120ceb996fff973c1de96b1ce7ec01ad9d0d845b5c7bc8a6`
uses the 1,420-byte producer slice, SHA256
`cccd7aac13040aa3d175181584d18575a209d922e861c57973bf994fa0dd9030`;
full-image instructions resolve its external tail and corroborate the order.
steps and `Get Started` only for setup's final ready step. These facts apply to
setup; they do not establish the separate menu wizard's presentation.

The password upload view's click and drop actions do not introduce a separate
animation transaction. The retained root/reducer analysis is corroborated by
sends the same action without animation. The state/root handlers likewise add
no local transition. This supports retaining immediate upload-state changes;
it does not remove the parent's separately attributed step transition (OB32).
The fresh action-slice REA call returned Java-probe timeout errors, so
`ev_bb8c9f0820992ffa40bf28a5657df7d48833880ce0b3d17c0e1a7b97fb85e928`
is retained as a failed attempt, not decompilation evidence.

The actual coordinator passed 138 isolated import/access/password assertions,
including bookmark-before-password ordering, exact destination preservation,
no duplicate commit/reopened results, empty-bookmark omission and both normal
and cancelled native completions after Stop. The 178-source whole-module Swift
check passed with warnings as errors, zero diagnostics and 278 unchanged inputs
in 232.51 seconds at `ce2c611`. Receipts are in `work/onboarding-import-order`;
no browser, personal source or credential reader was exercised.
Reconciliation through `1a3b509` adds independently checked pane geometry and
Favorite adoption changes; the import source and checks are unchanged. That
reconciliation is source-reviewed, not described as a second whole-module run.

The conditional password-method choice was identified before the implementation below:
`i-cloud-passwords-in-onboarding-enabled`. Parc must provide the included
local experience without that remote client. The following delivery establishes
the action and installation owner as well as the choice composition.


### Safari password choice and finish-owned installation

The included macOS14+ Safari setup branch now presents the original two-option
choice: Add iCloud Passwords Extension / Recommended, or Import Passwords from
Safari / Manual. The recommendation starts selected. Row selection changes only
pending state; Next accepts that choice. Manual continues into the real existing
CSV importer. The extension path omits CSV, persists its captured Profile in the
local setup draft and submits the actual installation only after successful
setup completion and browser preparation (replay installs it after Finish).
Skip, cancellation, stale Profile/Space ownership and unsuccessful setup
completion cannot install it.
The extension operation outlives the welcome window and reports genuine native
completion. A clean embedded import continues into the next setup step without
the separate menu wizard's results page; warnings/errors remain visible.

Both choices now use the same source-owned RadioGroupLabel component as the
default-browser step: 339 × 67 rows, 22 gap, 24 leading inset, 19 indicator gap,
250 label width, 15 continuous corner, 1.5 stroke and the attributed hover
spring. Password labels have medium 16-point titles and regular 13-point,
half-opacity subtitles; neither password row opts into the preferred heart.
The original title is “Autofill your passwords.” and its two-paragraph
explanation is retained with Parc's name. The default-browser row composition
is preserved by the shared component refactor.

**Recovered reference:** the retained Arc1.122 executable and SHA above.
REA `ev_9ac1f96f414585079126f2f0a9a204d0445b37fb5804dce58d2cdc4bcd8fff5a`
slice (SHA256 `5edaccefbdd95468c55a6d3c253390a1800db020b91da929f4446a7ed9fb35b1`).

That case is Apple's `pejdijmoenmkgeppbflobdenhhabjlaj`.
REA `ev_cc78d26d3abbde99bb9a0a1bdabba245faf35c2ee7ccba854ed7c55cd8d57b21`
`47b4134fb68e6ffaa47dcfadeac3a4d1bf017dcdf03a377ea8fc2c9e285e470b`).
Full-image instructions resolve the first function's external tail. The
`installExtensionFromWebstore:unattended:completion:` with unattended true.
The original Profile and completion survive the setup view; installation is
not a Web Store tab navigation or a consequence of simply selecting the row.

**Independent implementation:** the fixed-purpose native entry point uses the
captured regular Profile and real Chromium WebstoreInstallWithPrompt. Its
already accepted setup choice supplies no second install prompt; Chromium
retains metadata, signature, policy and CRX validation. The session retains the
actual request context until terminal completion and defers release beyond
Chromium's callback stack. Upstream WebstoreStandaloneInstaller already observes
Profile destruction and performs its own abort/cleanup; Parc does not duplicate
that lifecycle. Child profiles are explicitly refused because this setup path
cannot supply required parental reauthentication. Parc locally enables the
These are stated current-Chromium and local-service adaptations.

**Checks and limits:** the final 183-source whole-module Swift check passed with
warnings as errors, zero diagnostics and 283 unchanged inputs in 77.23 seconds.
After reconciling main through `31d226f`, the complete 183-source/283-input check
passed again with zero diagnostics and unchanged inputs in 316.32 seconds.
The actual pinned native compilation command passed a syntax check with frozen
Parc headers/source, zero diagnostics and unchanged inputs in 54.53 seconds.
The actual coordinator passed 153 isolated import/access/password assertions,
including macOS13 fallback, macOS14 recommendation, manual continuation, captured
Profile ownership, deferred acceptance, stale actions and cancellation. Draft
tests cover pending-choice resume and legacy drafts without authorization.
Actual isolated light/dark renders of both password selections and the shared
default-browser choices were inspected. Their shape, label and indicator layout
are intact; the fixture uses a fixed tint, so it is not evidence of the full
setup window's dynamic theme contrast.
The native installation itself was not executed: functional browser tests remain
prohibited. The 540-target overlay230 check passes with identity
`725c5602b6f687475c033d23776dee2409ec89ae38cb026536eec4fdba2f0ec1`;
native source/header hashes remain unchanged after reconciliation. The new native
bridge requires the next independent engine rebuild.
Receipts and raw REA material are in `work/onboarding-password-choice` and
`work/arc-onboarding-presentation`, outside Git. Remaining full import content
comparison and whole-flow order/presentation keep OB18/OB17 LEFT; no partial
requirement credit is claimed.


### Import content and initial bookmark recommendations

November 8 correction: Josh's import cleanup ("Two-colour import backdrops,
all ticked, no Profile step") replaced the five-page recommendation below.
Setup now starts with every bookmark ticked and the bookmark step has no
description; the recovered recommendation is kept here as reference only.

The five included import presentations now retain their recovered title and
explanation: source selection, Safari access, bookmarks, Safari password method,
and manual password export. The bookmark screen recommends five pages; it no
longer starts by selecting the entire source tree. Its initial choices come
from that source profile's actual imported history, ranked by visit count.
Only matching bookmark URLs qualify, the first duplicate bookmark is retained,
and up to five leaves are selected. Top-level folders start expanded. Users can
select a sixth page, whole folders or Select All normally; accepting the result
retains original URLs and ancestor folders. Missing or unreadable history yields
no invented recommendations. The application-menu importer's existing selection
policy is unchanged.

The native import result carries source visit counts alongside its bookmark
tree. Counts are captured from the genuine History batch already read by the
source importer; there is no query of the destination or another Profile.
Safari/Firefox can emit one row per visit with a repeated aggregate count, so
the snapshot retains the maximum rather than summing those rows. This is source
read data, not a claim that a failed destination write succeeded. Native result
warnings and category outcomes retain their existing independent meaning.

**Reference:** retained Arc1.122 arm64, SHA256 recorded above. The setup copy
`ev_386497da8e973d8001b3948abbee8f69bc368b4da56c8ca6c0d8aeb2debb2929`
from the 2,412-byte slice, SHA256
`27f9fab3975f4acea6a0b25caa13a3e24c0378a8dc8d16715c13b368b424557a`.
this is a recommendation rather than a selection cap. Parc omits the original
the original manual-export sentence, and uses its own name. These copy
adaptations do not add a service or claim a Parc usage statistic.

REA `ev_c7db56f7d903c36ede412bed8c49f53e27d1cacd3c893c19e490c44b1c24c7d1`
`c438d608e0e7c861782bff8c7a0f6ec2b6835052ee14b4dcf66c50e52f56d61b`.
REA `ev_e81f49b18eca2b18d9f3baffa256517ddcd0c2533d4605e5927a4e4ffcd1711d`
resolves the sort and existing-selection guard. Original Swift field metadata
identifies HistoryItem.visitCount; its comparator path
descending. The selector walks URL leaves, intersects actual source history,
parent reducer invokes the selector after both bookmark and history arrival
Parc creates its initial selection once from the completed source result, so
later row actions cannot be overwritten by an asynchronous recommendation.

Identity matching uses the recovered NormalizedURL behavior: lowercase the
comparison URL, supply https for a missing/http scheme, strip leading www,
remove ordinary fragments and one trailing path slash, preserve distinct
hashbang routes while trimming their final slash, and omit empty/utm_ query
items. Actual bookmark navigation URLs are never rewritten. REA
`ev_96bc166024b492e4607f25cfb7e35fffae7c4e20bc10c36360958acae7c7d1ac`
`bf9b7f99d1f8010de06bacbc9afd8c145c42bd3607206c7e246199297b81ad14`.
fallback behavior is supported by the full-image bound instructions instead,
not that failed pseudocode. Ties use deterministic source-tree order and
normalized duplicate history keys retain their maximum count: these are
ordering is not claimed.

The import presentation comparison covers the existing source/profile card,
bookmark list/folders, access illustration/actions, password-method rows,
manual export/upload/result controls and parent-owned help overlay. The bookmark
flexible height, border, clip and light-scheme environment without an outer
padding modifier. The inherited 24×16 source-row inset has therefore been
removed from this list; the white surface now fills its actual parent frame.
Independent discovery/progress/error messages, permission/restart actions and
stable result tokens remain the previously documented native-engine adaptations.
The extension-import presentation belongs to OB22, whole-flow step conditions
to OB17, parent motion to OB32, and full traversal to OB33; none is removed or
closed by this content increment. These boundaries are the existing fixed
requirements.


**Checks and closure:** the final 186-source Swift whole-module check passes
with warnings as errors, zero diagnostics and unchanged snapshot inputs in
173.79 seconds. The actual pinned native import-session command passes with
zero diagnostics and unchanged source/header inputs in 37.73 seconds. The final
selection/store model passes 87 assertions; the coordinator passes 156 isolated
source/access/password assertions, and restart persistence passes five. The
coordinator receipt precedes only the normalizer's explicit original-URL fallback;
the final model and whole-module receipts include that fallback. No browser,
personal source or credential import ran.

The actual 967×548 setup card was inspected through WindowServer captures in
light and dark, with its full 384×430 list, original title/message, five selected
leaves and expanded folder. An initial cached-view capture disturbed SwiftUI's
native row backing; repeating the same appearance transition with only window
capture preserved every row. That defective capture is discarded; it did not
justify an application change. Manual-copy composition also passes 27 isolated
component checks and fits its real instruction column. These are component
appearance/ownership checks, not whole-flow or measured motion acceptance.

Reconciliation through `fdee2ae` preserves the independently checked Downloads
metadata and pane-title deliveries; the onboarding sources and native bridge
are unchanged from the final checked snapshot. That composition is source
reviewed, not misreported as another full compiler run. Overlay232 passes
read-only digest/context replay across 540 targets, identity
`915b5fa00311bbd3f9d4f38fd0a646396d19095ac43c42e9e1f6217bcdf9c37d`.
The active v230 workspace remains frozen and was not modified; the new source
requires the following engine increment. Scratch and receipts remain in
`work/onboarding-import-content`, outside Git. OB18 is complete under the
current production-implementation rule, with no new runtime gate or change to
the fixed requirement denominator. The other first-launch requirements above
remain open in the parity ledger.

## Favorites setup content and selection

cases, but this screen reads the **nine** tags in the static array at
Slack, Figma and Outlook. WhatsApp and Notion Calendar are not grid choices.
apps you use most.” and “Select your favorite apps to keep them handy in your
sidebar.” Setup content case6 embeds this view; case5's 0.83 scale belongs to
the theme editor and is not a Favorites modifier.

`Setup.State.selectedTopApps` is `OrderedSet<TopApp>`, at state offset0x138.
catalogue order or append-in-click-order.

Parc's draft now records that order while retaining the previous optional-order
migration and saved choice set. New drafts use the original two choices;
older drafts retain their own selections. The real session commit uses the
ordered selection and existing transaction/rollback. Only the previous Parc
YouTube and Notion aliases normalize; previous explicit Google/GitHub choices
remain commit-capable without becoming extra grid choices. Unknown URL/order
entries cannot create Favorites. Replay adds only newly chosen Favorites; ones
the Profile already has stay selected. These are compatibility adaptations for
Parc's already-persisted drafts.

The native SwiftUI component retains one host while selections change. The
reference body is a 493×505 sidebar illustration, offset20×20 and aligned to
the bottom trailing corner of the setup content. Its rounded23 surface uses
white1 in light mode / white0.1 in dark mode and black0.2 shadow radius11,
x3/y2. The leading content has three24-point traffic circles, spacing15,
leading30/top42, a28-point gap and a three-by-three94-point tile grid with
12-point gaps. The two rounded21 placeholders are302×57; the right decoration

and40-point artwork clipped at corner4. Selected tiles add the same artwork
blurred20, saturated3, opacity0.6 and scale2.5, plus an inset3 rounded17
white Display-P3 overlay at0.7 with lighten blending. Unselected tiles have
the primary0.02,1.5-point border. The membership helpers return an optional
index: tag0 means found; interpreting it as a Boolean reverses the two states.
and spring(response0.18,damping0.8,blend0). Stale exits cannot clear a newer
opacity0.75 and spring(response0.2,damping0.4,blend0.5). Tiles use the pointing
hand cursor. Parc retains native buttons and accessible app names/selection,
with explicit Reduce Motion handling and disabled/detached-owner guards.

REA body evidence:
`ev_4a8c02d7a4d55b78d57a11cdb6050aba173a41b818fa66b0542803ef0403773d`
(5/5), tile evidence
`ev_8dd515e280ae50e70200e3b7b937dea94939c6363830a843d08aa35fef73f580`
(4/4), and press-style evidence
`ev_0b125d8f01fd5153d2b3508f594eb915c23a8689fe1b34855802934d842e2e4e`
(1/1). The bounded raw imports are tied to the retained full-image type
metadata, SwiftUI import bindings, action switch and constant data; pseudocode
alone does not identify those dependencies or recover original source.

Artwork is exported from the installed Arc1.170.0 (89123)
including Twitter's distinct light/dark rendition. The current catalog uses
X artwork for its `twitter` key. It is deliberately the installed reference
artwork, not a claim about the older executable's pixels. The ten PNGs are

Validation is deliberately scoped. The pure session/draft checks pass for the
original defaults, front insertion, removal/reselection, durable ordering,
old draft migration, duplicate aliases, unknown entries, commit/retry/restart
and failed-save rollback. A full 190-source application whole-module typecheck
passes with warnings as errors; the final native component compiles the real
19 app/model inputs, including the illustration's card-corner clipping.
Actual WindowServer captures show the complete light and dark setup card,
including all nine bundled images and the two original selected tiles.
The disposable harness could not expose SwiftUI virtual buttons through direct
in-process NSAccessibility traversal; its action assertions did not run, so
this is not an accessibility or native-input acceptance claim. No production
behavior was changed to accommodate that harness. OB33 and the complete-flow
appearance comparison remain LEFT. No browser test, engine launch or real
profile was used. Commands, source hashes and images remain outside Git in
`work/onboarding-favorites`; no one-off helper is shipped.

## Ready step, motion, focus, audio and haptics

ARM64 only, SHA256 recorded above. Helpers: `components.py`, `arctypes.py`,
`arcfn.py`, `arcidx.py`. No decompile slot.

### OB23 finished ready/reveal

interpolated value is `MembershipCardConfiguration.name` from Setup.State.
Show it off to the world or keep it to yourself.\n\nAnd with that, you’re now

hover and scale. Setup.Action `randomTapped` (14) and `downloadTapped` (5)
for tag 10.

NewSetupView stores `_confetti: Int` and `_direction: TransitionDirection`.
`eor !reduceMotion` into the counter, so Reduce Motion writes 0. Confetti
angles.

Parc now presents the local membership card on the finished step, interpolates
the card display name into **Welcome to Parc, %@.**, uses the recovered
description with Parc naming, and fires a Reduce Motion-gated overlay when
entering ready. Share/Download/Randomize are the recovered actions, in replay
too. Reveal still closes
added alpha fade.

Remaining: exact `ConfettiConfig` defaults; UserCard accessory layout vs
is Help → Getting Started, not this finished setup step.

### OB32 Back/Next and theme/step choreography

Setup.Action `previousButtonTapped` (15) and `nextButtonTapped` (4,
`isSkipped`) are the recovered controls. Progression enabled animation remains
and applies a Reduce Motion-gated push on the card content, heading and
message. Exact SwiftUI transition edge/duration was not recovered from
preview still updates `backgroundExtra` / `maxContrastColor` on the existing
card without replacing controls. Remaining: recovered duration/easing for the
step push, and any additional theme-crossfade besides the editor’s own motion.

### OB33 keyboard, focus and VoiceOver

Welcome headline is one header element; Get started remains the default
action. Setup heading reports `AXHeading` (the Swift `Role.headingRole`
symbol is macOS 26+). The card is a group labeled by that title.
Finished-step card is one image plus Share/Download/Randomize in the Tab
loop. Help overlay already traps Tab and restores the original responder.
Focus now moves to the space-name field only when **entering** theme, to
Next/Get Started when entering another setup step, and to the welcome host
only when first entering welcome. Auto-advancing welcome phases no longer
steal first responder. A layout-changed announcement fires when the stage
changes. Back, Space name, card actions, Skip (when visible) and Next form a
key-view loop.

Setup.Action `onPressEscape` (19) shares `modalBackgroundTapped`'s handler
November 9: every step's own choices are now in the key-view loop (see the
November 9 comparison); VoiceOver speech and Full Keyboard Access focus rings
remain unheard and unseen.

### OB34 audio interruption/mute/focus

UnboxingViewController field `musicPlayer` (`AVAudioPlayer?`) is started at
`applicationDidResignActive`, `windowDidResignKey`, or
`audioPlayerDidFinishPlaying` observer. Whole-image string search found no
AVAudioSession or interruption name.

Parc now owns that policy explicitly: start only from welcome, stop on
close/finish/terminate/replay, and ignore resign-key/resign-active/stage
changes. System output mute remains authoritative. Onboarding has no other
(SHA-256 `32646cdf…7e0a`).

### OB35 haptics

`performFeedbackPattern:performanceTime:` has fifteen 1.122 callers. None
are in AuthFeature/Unboxing `0x10166`–`0x1016f`. The onboarding-adjacent
Modal V2's drag-to-dismiss (`ModalContent.ModalV2HostView`, 152-point
threshold), not onboarding. All fifteen sites are attributed and SwiftUI
haptics are unused, so no welcome/Next/confetti haptic exists or is
synthesized.

### OB36 first-launch inventory and appearance

Recorded first-launch interaction/state now includes: welcome phases and
deadlines; setup order bookmarks → favorites → theme → default browser →
ready; finished-step UserCard/confetti/Get Started; TransitionDirection;
music start/stop vs focus; theme-editor haptics; membership-card
Parc screenshots across every step, theme-editor
onboarding composition (OB20), conditional import/extension branches
checks cover the new policy. No browser functional test ran.

## Theme step editor composition

than dropping the stock 356×508 Space popover into the right column. Helpers
`4e452201e483b5480c0403a9ef8566e10515cdcb78828622ff9032b202e29547` without
decompilation: `components.py`, `arctypes.py`, `arcfn.py` and `arcidx.py`.

`AuthFeature.Setup.State.Step.spaceStyleEditor` is case 5. `NewSetupView`
`SpaceStyleEditorView` with `Presentation.setup` (the zero tag of
color—add your favorite shade to your new home on the internet.” Comments are
“Title for theme step in onboarding” / “Description for theme step in
“Click to pick a color” for the Unboxing editor; the sidebar empty-state at

clear shadow configuration so the parent can own the drop shadow.
`OnboardingThemeEditorPopoverBackground` is that wrap: `NSColor.clear`,
8+8). Setup hides the stock editor's own popover material so the wrap owns
that chrome; the sidebar editor keeps it. NewSetupView then applies black
opacity fade and keeps the settled 0.83 scale. `SpaceStyleEditorBackgroundView`
behind the scaled editor. Parc's `OnboardingThemeEditorHitRegion` fills the
content column behind the 0.83 composition so padding clicks do not fall
through the card. The color pad is the recovered 340-point square. The stock
sidebar editor still uses “Tap to pick a color for this space”, 356×508 and
corner 12; setup still uses “Click to pick a color”. Unscaled `shadowPath`
step. OB20 stays LEFT.

Parc's first-Space name remains a left-column accessory. Setup.Action has no
name-text case, so this field is the existing draft `spaceName` rather than a
palette fill/placeholder, and no bezel or focus ring. Theme preview still
drives `backgroundExtra` / `maxContrastColor` on the original card and Next
control. Replay applies the light/dark choice as first launch does and
restores the previous appearance if it is closed early.

The stock sidebar editor is unchanged: 356×508, corner 12, popover material,
no unboxing empty-state copy. Setup presentation is `OnboardingThemeEditorChrome`
around that same `SpaceThemeEditorView`.


Eleven bounded comparisons (welcome, step order, import, Favorites, theme,
default browser, extensions, ready/reveal, transitions, keyboard, audio)

- Welcome: content from phase two (logo about 4.3 s, headline 7.3 s, arrow
  steps one phase); 0.2 s crossfade into setup; running dim not cut off.
  in place; title and description slide 400 pt on springs 0.4/0.8 and 0.5/0.8,
  opaque, old and new both drawn; no slide from welcome; import pages move the
  same way, backwards after Back. Back is `arrow.left` + " Back"; description
  15 pt, kern −0.3, 21 pt lines. Reduce Motion keeps the fades and skips the
  the starting theme); Favorites Skip selects none (Replay keeps existing
  every page but source choice; Stay logged in keeps Next disabled until a
  file imports; Back is hidden on the finished card; an import that finds no
  browsers is skipped.
- Default browser: Next never waits on macOS (above).
  0.4 s after arrival, once per window), "Welcome to Parc, %@" without a full
  stop, Randomize squish 0.93, Share/Download/Randomize tooltips, no "Card
  saved.", free-standing save panel named `<name>_Parc.png`, share text "I
  just set up Parc!".
- Keyboard: Command-Q works during setup; Command-W closes an open password
  help panel first; in Replay a key browser window's Command-W closes its tab;
  Tab reaches each step's own choices with Full Keyboard Access.

Parc-only additions kept under the never-remove rule: the Space name field,
the step counter, Favorite name tooltips, Replay, Stop Import and the Safari
access helper buttons. Open decisions for Josh, defaults followed: Favorites
slides, uBlock Origin Lite if uBlock Origin won't install, no seeded starter
folder. Not verified at runtime: VoiceOver speech, Full Keyboard Access focus
