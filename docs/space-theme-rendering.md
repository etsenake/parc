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

Only the physical window surface owns behind-window material. A floating sidebar
uses popover blur on the side its Space resolves to, the forced side or the
window's when automatic, so forced text never sits over a contrasting blur; see
[sidebar motion](sidebar-motion.md#floating-surface).

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
strip position. During settling, the retained `pagingSourceID` pairs source and
target, so commit/rebase does not restart the theme. A locked sidebar draws no
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

The strip positions the selected page and its immediate neighbors. Tracking
beyond one page can expose empty strip space while the background advances to
a later pair. Release selection remains bounded to one page from the starting
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
palette components cover their shared boundaries. Sidebar paging and floating-
surface components check pair/progress continuity and material layering.
