# Space theme material, text and motion

SPACE17 keeps three separate appearance owners: the original native window's
backing appearance, the theme's translucency material, and the contrast-selected
appearance of content over that theme. Editor previews, completed presets and
theme Undo publish the complete palette immediately through the existing window
callback. Space paging retains its separate transition owner.

## Recovered contract

`4e452201e483b5480c0403a9ef8566e10515cdcb78828622ff9032b202e29547`.
Retained `theme-picker`, `theme-render` and Sidebar evidence plus the local
components/type/xref/annotated-function helpers resolve this row. No second
version or new heavy decompilation was needed. Annotated receipts are retained
in `work/spaces-profiles-checks/space17`.

- `WindowTheme.Background` stores `contentOverBackgroundAppearance` and
  `isVibrant` separately from its style. The style has its own optional
  `TranslucencyStyle`; the theme stores a separate appearance-based semantic
  palette. These are not interchangeable dark-mode flags.
  blended style with light translucency (zero at the single-color `+0x20`
  or gradient `+0x10` style field). Noise, intensity and texture remain the
  stores it at Background `+0x39`, and sets vibrant at `+0x3a`. It does not
  replace the style material with that contrast choice.
  local override. Applying explicit label colors alone omits this native
  semantic-content path. The editor's empty/failed projection falls through
  style against the current appearance. Light and Dark use native material
  and absent style falls back to the effective appearance. Construction
  material exists only when an explicit from/to transition needs a different
  style, with its alpha supplied by that transition's progress.
  to `0.2 + 0.55 × intensity`; underlay alpha is capped at 0.5, multiplied by
  0.35 for the black dark underlay. The existing 32×32 gradient target,
  OKLab interpolation, premultiplied texture pass and full-window sampling
  remain the retained source-owned renderer contract.
  parent windows and accepts key or main state. It observes all four key/main
  quartered only for inactive ownership; the editor becoming key must not
  dim its still-main browser window.
  page-tracking state, removes duplicates, maps to a **single** background
  operator. Space paging separately produces `transitioning(from:to:progress:
  introduce a timed background fade or queue previous color edits.
  position response 0.28/damping 0.63, with zero blend duration. Position
  These constants and immediate direct-input behavior already existed in
  Parc. SwiftUI owns replacement of its animations; Parc's explicit Core
  Animation layers need equivalent retirement and replacement.

### Texture alpha (October 31)

strength formula and tiling were already right; the texture data was not.

  `ThemeOutputUniforms` already matched, so the inactive quartering stays.
  per 100 points at every backing scale, which matches Parc's `pointSize / 100`.
  extended sRGB. Parc's canvas keeps the MTKView default of sRGB, which the
  rendering check asserts; for 8-bit unorm output the two are identical.
- [D] Installed 1.170 `ARC_WindowThemeUI.bundle/default.metallib`, read with
  `llvm-dis`, because 1.122's bundle is not retained: `overlayFragment` divides
  RGB by alpha, then multiplies by `alpha × strength`. `renderFragment`
  composites `overlay × (1 − bg.a + bg) + bg × (1 − overlay.a)`, which Parc
  already re-expressed.
  same loader its texture averages 48.5 RGB at alpha 66. The exported
  `ThemeTextures/grain.png` decodes as straight `last` alpha, averaging 187 at
  alpha 66. Reading it as premultiplied added roughly 3.9× the texture and a
  net brightening (`bg × (1 + s(rgb − a))` instead of `bg × (1 − s·a(1 − rgb))`).
  Sand, denim and tweed are opaque, so only grain changed.
  monochrome because of its premultiplied amplitude. It is not a luminance mask.

The real `ThemeRendererView` was read back offscreen at 2× with key
ownership on and off, then passed through the same 0.638 downscale and JPEG
0.62/0.34. Before the fix, Parc measured 6.27/2.09 and 2.20/0.73. The same
pastel theme's mean sidebar color moves from washed-out (248, 242, 243) to

### Space paging

floating sidebar does. Parc's window surface used to take the new Space's
disassembly, the cross-reference index and Swift field metadata, with no
decompilation. The shaders come from the installed 1.170
`ARC_WindowThemeUI.bundle/default.metallib`, because 1.122's bundle is not
retained. Its six AIR modules were extracted and read with Homebrew
`llvm-dis` 21.

  pages and the page width is positive.
    the pages at the floor and ceiling of the strip's fractional position
    (`frintm`, `frintp`), each clamped to the strip.
  - While the paging animator runs, it instead pairs
    `WindowLayoutController.pagingAnimationSourcePage` with the controller's
    target page, when both exist and differ. Where that source page is set
  - Progress is `(position − from) ÷ (to − from)`, clamped to 0…1. So `from`
    and `to` are the left and right pages, not the current and next Spaces;
    while tracking, the configuration depends only on the strip's position.
    `WindowLayoutController.backgroundView` (field 3) and to
    `floatingSidebarContainer.themeView`, whatever the sidebar's mode.
  - `shouldCrossfade` is `WindowState.sidebarMode == .noChrome`
    (`BaseModels.SidebarMode`: `anchored`, `noChrome`; compared at
  configuration with no timer (above). [I] A cancelled or committed swipe
  springs to a page origin, where the mix is that page's theme alone, before
  `single` returns, so neither settle jumps.
  of two renderers:
  - `WindowBackgroundViewExperimental`, whose theme view is
    `WindowThemeBackgroundViewMetal`;
  - or the SwiftUI `WindowBackgroundViewLegacy`.

  Its creators take the choice from a publisher of the
  `metal-window-background-rendering-enabled` and `use-metal-by-default`
  installation uses is not recoverable statically. Parc's renderer
  re-expresses the Metal one.
  (`progress`, `layerCount`, two `GradientLayer`s), one layer for `single`
  and two for `transitioning`, and passes it to the gradient pass
  `shouldCrossfade` (`+0x108`).
  - `gradientFragment` takes each layer's straight colour over its underlay
    (`layerColor`). With two layers it computes `mix(from, to, progress)`,
    alpha included, before premultiplying.
    `mix(from × fromOverlayAlpha, to × toOverlayAlpha, progress)`
    (`OverlayRenderConfiguration`); a missing texture contributes 0.
  - `renderFragment` composites the result as for one theme.
    called twice with it).
  it stacks the `from` view, at opacity `1 − p` when `shouldCrossfade` and 1
  otherwise, under the `to` view at `p`.
  gives its background material the `from` style. When the `to` style
  differs it adds a foreground material once, with the `to` style at alpha =
  progress; otherwise it hides it. The floating container hides that
  translucency ([floating surface](sidebar-motion.md#floating-surface)).
  [I] The window's container keeps its default and shows it.

tracking does (`SidebarSpacePagingModel.themePages`, `onPagingTheme`): the
themes of the pages at the floor and ceiling of the strip's position, left
first, and the fraction between them. That holds wherever the strip is:

- a drag past one page;
- a second discrete page during the first one's spring;
- the pager's commit, which re-bases the offset on the new Space but leaves
  the strip's position, and so the transition, unchanged.

The controller gives the transition to the window's root surface and to the
sidebar's surface (`ThemeRendererView.pagingTransition`). Its `from` is always
the left page, so while it is set the surface's own theme is not drawn:

- A locked sidebar's surface draws no background, so the window's surface
  shows through the sidebar and pages as one.
- A floating sidebar's surface pages too, sampling the same full-window
  gradient.
- A hidden sidebar cannot begin a swipe until it is shown floating, as

The renderer follows the Metal path:

- One gradient pass mixes the two layers' straight colours by p and then
  premultiplies.
- The display pass mixes the two strength-scaled textures by p and
  composites them over that.

Only the window's own surface (no `coordinateSpace`, not floating)
displays translucency through a swipe:

- Its base material takes the left page's style.
- When the right page's material or appearance differs, a second
  behind-window material (`pagingMaterial`, created on first need) carries
  that style above it at alpha p.
- At rest, the base material returns to the surface's own style, and the
  second one is hidden there and wherever the surface draws no background
  or no material.

The sidebar's surface never builds a second material, including a locked
sidebar that floats mid-swipe.

Each frame costs one canvas draw per surface, plus that alpha while the
styles differ. The transition's pipelines are built on the first draw that
pages; it no longer allocates a second gradient target.

Adaptations and gaps:

  floor-and-ceiling pages through the spring too. They agree whenever the
  two pages are adjacent and the strip lies between them. A second discrete
  swipe began is not in the retained evidence (only the release target is
- Past one page, Parc's strip draws only the selected page and one
  neighbour, so the page beyond shows empty while its theme mixes in.

  Parc treats an uncoloured Space's layer and texture as clear, so the other
  theme fades as a whole.
- The two layers keep Parc's per-theme underlay side, which the forced-style
  compatibility above requires. For automatic themes this is the one window
- The SwiftUI renderer's stacked fade, the one place `shouldCrossfade`
  matters, is not reproduced.

**Checks.**

- `tests/FloatingSidebarSurface` renders the real canvas, floating and on the
  window's surface. At p = 0.37 the commit changes 0 levels on both, and the
  picture) and 11 from a crossfade of the two pictures. Built against the
  previous renderer, the mix check fails at 11 levels.
  - A commit with an uncoloured Space on either side changes at most 1
    level, and an uncoloured Space fades the theme the same from either side.
  - Past one page, with neither page the surface's own theme, the picture is
    the same.
- `tests/SidebarSpacePaging` checks `themePages` against the pager's own
  offsets. A commit, a drag past one page and its release, and a second page
  during the first one's spring each keep the same pair and progress.
- `tests/SpaceThemeRenderingTests.swift` (`checkPagingMaterial`) covers:
  - the materials' order, style and alpha;
  - the left page's style as the base, the commit and hiding;
  - a sidebar surface that floats mid-swipe keeping one material. Without
    the `coordinateSpace` guard, this check fails.
- [C] An offscreen full-window harness (stand-in materials, real canvases)
  measured a light → purple swipe committed at 40 %. Before: the window
  margins jump 169 levels and the locked sidebar 68. After: 0 levels
  anywhere in the window, locked or floating.

## Production application

`ThemeSurfaceStyle` separates backdrop appearance and native translucency from
`ThemeChromePalette`. The main root and floating/sidebar preview surfaces use
the real window's appearance for the Metal underlay, even when a nested surface
lives below a content subtree with a contrasting appearance. A weak window KVO
observation keeps that nested backing current when an explicit ancestor
appearance masks normal AppKit propagation. It is replaced on reparenting and
released with the renderer.
The neighbouring page's palette comes from the window's real appearance each
time the page strip moves, so an unthemed next Space follows the window
appearance even under the current Space's contrasting text subtree and during
an application appearance change. It builds no renderer of its own. The
window's surface, and the floating sidebar's, draw a swipe by mixing both
[Space paging](#space-paging)).
On the floating sidebar, under a theme's colour, the popover blur resolves
`blurView` is inferred to [I], even for a stored forced Light or Dark
appearance. A swipe between coloured light-style and dark-style Spaces
therefore leaves it unchanged, and a forced side's text can sit on the
window's blur ([floating surface gaps](sidebar-motion.md#floating-surface)).
Where the blur is the whole backdrop (an uncoloured Space, or no Metal) it
takes the theme's side, in the window's own appearance whenever the window
is on that side.

Sidebar, Library and popup chrome apply `contentAppearance` to their existing
native view trees as well as the existing explicit semantic colors. Labels,
text fields, selection controls and native semantic fills therefore use the
same content scheme. Page/document ownership and the global app appearance are
unchanged. The parent palette callback continues to update the original
window's real chrome and opt-in website stylesheet; it does not reconstruct
views or commit a draft.
incognito theme in place of the Space's, an opaque basic colour with no
material or canvas and BrandBlue's palette in the window's appearance
([private window theme](window-appearance.md#private-window-theme)).
For an empty/invalid automatic theme, Parc explicitly supplies the original
window's full native appearance object. This expresses the original inherited
appearance while avoiding a nested neighbor inheriting the current Space's
contrasting text scheme; it does not reduce that inherited appearance to a
new Aqua/Dark Aqua object. Forced saved appearances remain explicit.

The material is emphasized and retains behind-window compositing and native
window-active behavior. Grain/sand/denim/tweed and intensity feed the same Metal
configuration as before, now with the correct backdrop appearance and activity.
The one physical gradient coordinate space remains shared with floating and
neighbor surfaces. Empty or invalid themes hide the Metal canvas and retain a
native material; Metal or texture failure keeps the existing native fallback.
When Metal initialization fails, the native material is the whole backdrop,
so it follows the content palette's light/dark choice to keep text legible.
Missing texture alone retains the normally colored canvas and native material.
The texture loader premultiplies a straight-alpha PNG once, drawing it into
a premultiplied-last bitmap in the image's own color space, and passes
opaque images through. The texture therefore holds the same premultiplied
and the display pass keeps the original all-channel strength scale. The bundle
still loads only the standalone PNGs.

`ThemeColorPadMotion` retains the recovered springs. It reads an interrupted
animation's presentation value before replacement, does not restart a spring
on a redraw with an unchanged target, removes positional motion when direct
input or layout takes ownership, and preserves positional motion during a
hover-only restyle. New knobs start at their target; an existing knob at the
pad's zero corner remains a valid spring origin. SPACE15's admitted `onBegin`
refresh retires motion before capturing the model knob center, even when the
first accepted color is unchanged. Reduce Motion settles both springs, including when the
preference changes during playback; detachment removes pending motion and the
observer holds the pad weakly. No animation owns an editor/model mutation or
deferred theme commit.

Explicit adaptations: Parc's previously saved forced Light/Dark themes retain
their old explicit backdrop and content choice instead of being migrated.
Reduce Motion and detachment cancellation are Parc accessibility/lifetime
policies. Current AppKit supplies the actual native material; reproducing the
historical operating system's private compositing kernel is outside the
source-owned renderer. The completed paging transition is preserved, including
its previously documented interpolation adaptation in `navigation.md`.

## Checks and delivery

`scripts/test-theme-rendering.sh` compiles actual production code and checks
native backing/content separation, parent appearance propagation, material
state, immediate/no-op theme publication, final-color removal, invalid themes,
key/main/parent ownership, actual gradient/texture uniforms and spring
interruption. It also reads back the real renderer's drawable for a mid-gray
theme, pinned at 400 pixels for a 200-point surface so a 1× display cannot
minify the grain tile. A discarded warm-up render absorbs one stale-size
drawable.
- Full grain must darken the surface slightly and must not brighten it beyond
  1.03× (measured 0.984).
- Its green-channel deviation must stay between 3 and 13 levels (measured 6.9),
  and inactive ownership must cut it by at least 2.5×. The inactive deviation
  measures 1.77 levels, 3.9× lower.
- The original straight-as-premultiplied read measures 1.53× and 26.7 levels,
  failing both bounds.
- Opaque tweed must match the original composite predicted from the PNG's own
  mean within two levels; its readback is identical before and after the change.

The check also asserts the canvas's sRGB output and snapshots the real editor
controls, in Dark and Aqua, for the [editor presentation](space-theme-editor.md)
values. Its 112 assertions include physical editor direct-start and detachment
cancellation, with the haptic performer silenced. The script copies the bundled
theme resources beside the binary. Its windows stay at offscreen coordinates;
no browser or engine is loaded. The integrated input component passes
124 assertions and original-window Undo passes 40. The appearance component's
72 assertions and WebsiteTheme's 53 assertions also pass.
The existing theme appearance/Undo/input components cover shared editor
boundaries, and WebsiteTheme checks cover unchanged public palette conversion.
Final integrated whole-module SIL and independent review receipts are retained
beside the focused results. Compiler and inert-component results establish
implementation behavior; integrated browser runtime and whole-product visual
acceptance are not claimed.
