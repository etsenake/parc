# Space theme material, text and motion

`ThemeSurfaceStyle` separates backdrop appearance/translucency from
`ThemeChromePalette`. Root, floating sidebar and preview surfaces share one
physical window-gradient coordinate space. Theme publication updates those
owners and optional website palette sharing without rebuilding views or
committing an editor draft.

## Production application

Native chrome uses `contentAppearance` and explicit semantic colors consistently
for labels, fields, selection and fills. The Metal underlay uses the real window's
appearance even beneath a differently styled content subtree. A weak window
observation follows explicit appearance changes and is replaced on reparenting.
Unthemed automatic surfaces receive the window's complete appearance object;
saved forced Light/Dark themes retain their explicit appearance.

Only the physical window surface owns behind-window material. Its light or dark
material, like the floating sidebar's popover blur, takes the side the Space
resolves to: the forced side, or the window's when automatic, colored or not.
Forced text therefore never sits over a contrasting material; see
[sidebar motion](sidebar-motion.md#floating-surface).

A colored Automatic Space picks its text side from what actually lies behind the
text. `ThemeRenderMath.chromeBackgrounds` samples the color layer where the
sidebar sits on the gradient, with its underlay, over the material's own color
and over contrasting content showing through the material. The palette takes the
side where white or black text would read better there, then moves the text and
accent colors toward white or black until they reach 4.5:1, or as far as they
go. Forced Spaces keep their side and get the same nudge only where they fall
short. Only the text and accent change; every other role keeps its side's color,
and colorless Spaces keep the window's appearance and system colors. Over bright
content, such as a white page or desktop, a dark-mode blur is itself mid-gray,
which limits contrast for every Space.

Private-window surfaces use a static opaque incognito background and BrandBlue
palette, with no material/canvas. Empty/invalid themes hide the canvas and retain
native material. Metal failure makes that material follow the content palette
for legibility; missing texture alone leaves the colored canvas intact.

## Texture alpha

Texture strength is noise × texture maximum × activity, with maxima grain 0.8,
sand 0.15, denim 0.6 and tweed 0.4; inactive strength is one quarter. The tile is
100 logical points per side, scaled to backing density. Intensity and texture
remain independent modifiers.

The loader premultiplies straight-alpha PNGs exactly once in their own color
space and passes opaque images through. Linear filtering uses premultiplied
texels; the display pass scales every channel by strength. The canvas outputs
sRGB. Standalone bundled PNGs are the only texture inputs. A second multiply or
straight-alpha upload changes both brightness and apparent noise strength.

## Space paging

`SidebarView.showPageStrip` publishes `ThemePagingTransition` to the root and
floating surfaces. During tracking it uses the floor/ceiling pages and fractional
strip position, clamped to the swipe's reach. During settling, the retained
`pagingSourceID` pairs source and target, so commit/rebase does not restart the
theme. A swipe that catches the slide from a click more than one Space away
keeps that pair while the strip stays on the departing page's side, and uses the
real neighbor once pushed past the clicked Space. A locked sidebar draws no
separate backdrop; the root shows through. Hidden sidebars begin swipes only
once shown floating.

One gradient pass mixes the two straight-color layers and then premultiplies.
The display pass mixes their strength-scaled textures and composites them over
the gradient. A clear/uncolored side fades the other theme as a whole. This is
layer mixing, not a crossfade of already-composited pictures.

The window's base material takes the left page's style. If the right style or
appearance differs, a second behind-window material takes that style at the
transition alpha. At rest the base returns to its own style and the second is
hidden. Nested and docked sidebar surfaces never create that second material; a
floating sidebar blends through its own within-window blur, described in
[sidebar motion](sidebar-motion.md#floating-surface). Each surface requires one
canvas draw per frame; the transition does not allocate another gradient target.

The strip positions the selected page and its immediate neighbors. A two-finger
swipe reaches only its starting Space and the Space either side, and the pager
publishes that reach until the strip comes to rest. Past the neighbor, or
backward from the first Space, the strip stretches with
[edge resistance](sidebar-motion.md#floating-surface) instead of exposing empty
strip. The theme position is clamped to the reach, so the background blends only
between the two Spaces the release can land on, including while the re-based
strip settles, and the strip parks any page outside the reach rather than
building it. Release selection remains bounded to one page from the starting
Space.

## Color-pad motion

`ThemeColorPadMotion` retains current presentation values when an animation is
replaced and does not restart on unchanged targets. Direct input/layout owns
position immediately; hover-only restyles preserve positional motion. New knobs
start at their target, including a valid zero-corner origin. An admitted gesture
retires motion before reading the model center even if its first color is unchanged.

Reduce Motion settles both position and hover springs, including mid-animation
changes. Detachment cancels motion and its observer holds the pad weakly.
Animation never owns a model mutation or deferred commit. Input, appearance and
Undo transactions remain in their focused guides.

## Checks

`scripts/test-theme-rendering.sh` covers backing/content separation, propagation,
material ownership, no-op publication, invalid themes, gradient/texture uniforms,
alpha readback and spring interruption. Theme input/appearance/Undo and website-
palette components cover their shared boundaries. The appearance check also
verifies text and accent contrast for Automatic and forced Spaces across colors,
intensities and both appearances, and the docked material rule. Sidebar paging
and floating-surface components check pair/progress continuity, a swipe's color
staying within its two Spaces, and material layering.
