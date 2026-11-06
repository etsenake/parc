# Window appearance and transitions

WIN15 owns private, page-created popup and ordinary browser-window appearance
and transitions. This is an incremental contract; the row remains LEFT.

## Private unpinned heading

“Incognito Tabs” for its incognito context. The unpinned header accessory is
Its section-header typography and horizontal placement are documented in
[sidebar resizing](sidebar-resize.md#space-header). Parc now uses its existing
section-header view for the private title and gives it the recovered 36-point
and sets its content insets to 8 top, 14 left, 2 bottom and 8 right
the left inset by 3.5 for incognito or 1.5 for a regular profile

with the tooltip “Incognito tabs” when `SidebarSpaceState`'s
than one Profile, as retained in [sidebar resizing](sidebar-resize.md#space-header).
and the section header builds the full-size indicator without a chevron
case 0). The cell creates the header with no profile-menu provider
centered in a 20-point slot, 2-point spacing, 5/6-point horizontal and
4-point vertical padding. Its background is a continuous Capsule
SHA-256 `00674b605547c90f7f6e2484a17058c19fda16b38a33112ff1e52c8901b54050`
provides Gray2 as sRGB 0.973 light / 0.11 dark and ForegroundTertiary as
black / white at 0.3 opacity; asset values are separate from the 1.122 usage.
WIN11 identified the application store already attached to the controller as
the read-only source for the original Profile count. Parc observes that count
and replaces the title with a passive, left-aligned indicator while it exceeds
one; its AppKit shape and static-text accessibility representation are
adaptations. The private sidebar model and WindowID remain separate. The
([below](#private-window-theme)). Its Extensions menu, remaining popup chrome and
complete window transitions remain under investigation. Popup and standard-window `close` thunks
a lifecycle action; that does not by itself establish their opening or
fullscreen animations. No functional browser test was run.

field and a left accessory of window controls or a close button. Its action
type includes Back, Copy URL, Extensions, close, maximize and expansion. That
inventory does not prove which controls a page-created popup displays. The
`ev_143243443529b1351df3221f0dadb864c512207858dc919621669d6ca786a3ed`)
is dominated by SwiftUI generic construction and leaves control composition
`windowControls` and `shouldDisplayURLField` to true; bounded decompilation
`ev_61095f2748be2af810966f7d9e9cb49bba5b16fff74ccaad5dab31c09d362e22`
confirms the assignments, with the field offsets checked against Swift type
metadata and annotated instructions. The body only creates its Back button
is unavailable and collapses its slot. Individual control builders and the popup-specific
state transitions remain the next reference targets. The outer SwiftUI body
does not contribute to that height: the earlier 46-point inference mixed
the neighboring offsets. Parc now uses 47 points for the popup strip. The
remaining horizontal placement and unrelated controls are adaptations.
or Reload action; URLField's callbacks cover Copy URL and Extensions, while
the left accessory is window controls or Close. Parc removes its additional
Forward and Reload strip buttons. The existing browser navigation commands
and page ownership remain available; WIN13 confirmed the menu/focus boundary.
The separate `LittleBrowser.URLField` type owns primary text, loading,
search/profile/insecure accessory, optional copy configuration and extension
button state, with copy and extension callbacks. That establishes component
ownership, not its exact layout or all availability rules. Its body
hover state feed its rendering. It also applies a 31-point minimum height
its 16-point image in a 31-by-31-point centered square. The label uses
Parc renders it with the already bundled IcoMoon font and its existing icon
asset catalog (SHA-256 `95565a4edee8c3cff16e3076de9405bc9cedaf2dea88785a749b9a9dc6947f03`)
provides the named normal/hover fills used by the 1.122 body: Display P3
`(0.055, 0.059, 0.063, 0.06/0.10)` in light and
`(0.98, 0.984, 1, 0.10/0.15)` in dark. This is asset evidence only; no
1.170 code address or behavior was compared. The 1.122 URLField's `_hovered`
state is field 9, and its body chooses the normal or hovered color at
shape behind its real address control and tracks hover in the key window;
AppKit tracking and color-change timing remain adaptations. The isolated
popup component check covers the passive background's geometry, shape and
sampled light/dark colors, including clearing hover when its frame moves away
from the pointer; it does not drive a browser.
default system FontSet supplies 13- and 11-point system fonts respectively
([label](web-interactions.md), [sublabel](parity.md)); Parc follows this selection from
the actual page loading state. Its exact loading indicator and motion remain.
The URLField's Copy control is conditional on `copyURLConfiguration`
actual popup URL and uses the live Copy Current URL binding. Its action
captures and revalidates the original page, window, document revision and URL before dispatch;
the centered label's equal-side clearance and row-button hover are AppKit
adaptations.

URLField creates its Extensions button when `shouldDisplayExtensionsButton`
producer counts enabled extensions on the little window's original Profile,
including extensions without toolbar actions ([carrier](extensions.md#popup-toolbar-enabled-extension-availability)).
Parc re-queries the guarded native page-scoped carrier when extension state
changes and presents the real Site Control Center from the popup control, with
the original window, page and document revision revalidated. A missing older
engine selector leaves the control unavailable. The current center uses action
rows and may omit enabled extensions with no toolbar action; its use and the
control's layout/hover are adaptations, not a claim of the original Little
Browser extension-menu contents. That remaining menu contract and the engine
build containing the new carrier remain open.
`isMovableByWindowBackground` true and a 300 × 360 minimum size (the latter's
this class for `WindowStyle.little`; page-created popups use the distinct
`.browserPopup` entry in that style ([ownership](download-library.md)). In
the local selector index, the constructor is the only `setMinSize:` and
`setMovableByWindowBackground:` call inside the LittleBrowserWindow code range;
this bounded search does not rule out indirect or external overrides. Parc
now applies those properties only to popup windows, preserving the original
requested frame subject to the native minimum. WIN12 and WIN13 have confirmed
the window-property interface. The other popup chrome remains an adaptation.
The isolated popup view check exercises Back appearing, disappearing and
releasing its layout slot with inert collaborators; it does not drive a browser.

## Private window theme

An incognito window never shows its Space's theme. When the incognito

- [D] **Background.** `.single(Background(style: .basicColor(color:
  translucencyStyle: nil), contentOverBackgroundAppearance: nil, isVibrant:
  false))`. The colour is `NSColor(displayP3Red: 0.054, green: 0.06, blue:
  translucency byte is 3, nil (`TranslucencyStyle` has light, dark and auto);
  the appearance and vibrancy bytes at Background `+0x39`/`+0x3a` are 2 (nil)
  The surface is therefore opaque: sRGB (13, 15, 19).
- [D] **Window appearance.** `.single(.dark)` at theme `+0x7c`
- [D] **Palettes.** The primary palette (theme `+0x80`) is the static
  colour conversion fails), converted with `colorUsingColorSpace:
  makes the same four luminance bands as a Space theme's (0.85–0.95, 0.3–0.5,
  appearance-based light/dark pair. BrandBlue is Display P3 (49, 57, 251)/255
  in the catalog; in extended sRGB it is (0.1842, 0.2248, 1.0241).
  resting fill when the window style is standard with sidebar context 2,
  hovered fill. The catalog gives the incognito fill as Display P3 white at
  0.15 in every appearance.
  mode: sidebar and window edge sRGB (14, 15, 19) with nothing behind the
  window showing through; URL bar (50, 51, 55), white at 0.15 over that;
  empty page (38, 39, 43), the empty content's white at 0.1 over that; no
  toolbar above the page. The pill's text and the New Tab and heading labels
  incognito tab row, whose title takes the palette.

Before this, a private window drew its Space's own theme, BrowserStore's
`.singleColor(#202020)` over the dark behind-window material: a translucent
dark grey with the desktop showing through. Parc now gives both of a private
window's surfaces `ThemeRendererView.incognito`.
They hide the material and the theme canvas and fill their layer with the
incognito colour: the window always, the sidebar's surface only while it
floats or docks (a locked sidebar shows the window's), inside the floating
surface's existing rounded edge and shadow. The palette is
`ThemeChromePalette` of `IncognitoWindowTheme.paletteTheme`, BrandBlue's
extended-sRGB components with the blue clamped from 1.024 to 1 because a
`ThemeColor` holds 0…1 (an adaptation of a few levels at most), resolved
against the window's Dark Aqua. The plus HUD, the Back/Forward history
chooser and tooltips take that same theme, so they show its light half in a
too, and the sidebar's hover previews already take the sidebar's palette. A
private window's download review panel draws the incognito surface and is
appearance to that panel is inferred, and without it a light app would put
the light half's dark text on the near-black fill. The website stylesheet's
`--arc-background-simple-color` is the basic colour; that a `basicColor`
background exports its one colour there is inferred from the stylesheet
Ordinary windows are unchanged.

reads both of its colour inputs from the window's theme context: the
incognito theme. Its background reaches the card as one colour:
(max + min) / 2, saturation over that sum or its complement) and adds its
saturation 0.163, so it gains 0.4 saturation and 0.3 lightness: a card tint
of P3 (0.159, 0.277, 0.570), white text, under the dark 0.2/0.4 gradient.
Parc's toasts and the cue in a private window take
`IncognitoWindowTheme.background` as that one colour
The semantic palette (the incognito theme's BrandBlue palette here) becomes
and the tracing view read; Parc's label, sub-label, keycap and share button
([toasts](toasts.md#card)).

page-created popup is a `little` window ([popup windows](#popup-native-window-class)),
incognito popup was not traced.

field is the application's `AppState.topBarDisplayedPreference` (field 33)
passed through `WindowsState` (field 3) to every window; that the scoping
copies it unchanged into an incognito window is inferred, as no incognito
branch was found. Parc shares one Show Toolbar preference across regular
and private windows ([settings](settings.md#ordinary-toolbar-appearance)).
On November 1 Josh's Parc had it on (`parc.browserToolbar.v1` isVisible true)
showed the bar and lost the URL bar and navigation buttons. View → Hide
Toolbar (Shift-Command-D) returns both, in every window.

traced (above). The empty URL bar now reads "Search or Enter URL…" beside
and the Press Again cue takes the incognito colour (above).

## Popup native window class

sets `isRestorable` false, `hidesOnDeactivate` false,
`becomesKeyOnlyIfNeeded` false and collection behavior `.managed`; its
`canBecomeKeyWindow` and `canBecomeMainWindow` overrides return true
those properties, retaining its existing native binding, close delegate,
request geometry and session exclusion. WIN12 and WIN13 confirmed these
interfaces. An off-screen native component check covers configuration and
key/main eligibility without ordering or activating the window.

`LittleBrowserEntryPoint` for `floatingWindow` (case 2), so `.browserPopup`
(case 7) takes the level-0 branch. Parc now applies the popup-only temporary
level and queues a weakly owned reset to normal and removal of
`moveToActiveSpace`, preserving the panel's existing key and close ownership.
WIN13 confirmed this interface. The reset is idempotent for repeated calls and
does not activate another window; no window activation or browser test was run.

The popup address context menu and its accessibility custom action retain access to Site Control Center when the conditional Extensions button is absent. Both acquire the original popup/page and revalidate its key window, security admission, native binding, document revision and lifetime before presentation; this fallback is a Parc accessibility and continuity adaptation.

## A window with no tab

no blueprint and no sidebar item: the same content Add Split shows as its
`4e452201…`), annotated disassembly:

  `bestMatchFromAppearancesWithNames:` against Dark Aqua; values from
  with the same color.
- [D] The Space's `contentOverBackgroundAppearance` never reaches that backing.
  follows the window's own appearance.
  under a gradient capped at 0.5 alpha ([theme rendering](space-theme-rendering.md)).
  Without an opaque page, that backdrop shows through the content.
  empty content is within a few levels of the sidebar beside it (224, 218, 202
  → 228, 222, 206), white at 0.1 to within rounding, and the windows behind

Parc shows `SplitPanePlaceholder`, which already carried the color for Add
Split, as the window's only content. It has no subviews, takes no input and is
recovered). The page host clips it at the shared 6-point continuous corner over
a clear backing, so Parc's existing translucent theme backdrop shows through.
The former Parc start page (wordmark, search button and shortcut hint) is
removed. A tab with no address yet (about:blank with no native page) shows the
windows too. It has nothing to focus, so selecting it, closing the command bar
over it or restoring its focus gives first responder to the window (taking it
from a parked previous page) and ends the focus request at once.

## Page card shadow

content black at opacity 0.25, radius 3 and offset (0, 1). A second Boolean
from that publisher switches to radius 8, opacity 0.35 and, in Dark Aqua,
white; which view-state field it is was not decoded [I: the modal content].
[O] The 1.170 empty-content edge matches the ordinary shadow: darkest just
below the edge and gone within about 6 points.

Parc draws that shadow outside every page card, empty content included:

- `ContentShadowImage` renders it once per scale into a 51-point stretchable
  image (10-point outset, the 6-point `PageCard.cornerRadius` and 9 points of
  straight edge either side of one stretchable point). The casting shape is
  drawn a canvas away so only its shadow lands, then the card's interior is
  cleared through a mask Core Animation draws with the cards' own continuous
  corner. A translucent card is never darkened, no fill fringe remains at its
  edge, and a resize never re-blurs. Core Animation's radius 3 is drawn as a
  Core Graphics blur of 6, and the shadow offset is scaled to device pixels.
- A lone card is clipped by the page host, whose edge moves inside ⌘S while the
  page is laid out at its final size. Its shadow is `PageCardShadowView`, the
  page host's sibling below it, placed by both chrome passes and moving in the
  same ⌘S group. It refuses hit testing, is not an accessibility element and
  never redraws on resize. It hides while the split is divided and while a page
  fills the window in full screen.
- A divided split's panes clip themselves, so `ParcSplitView` keeps one shadow
  layer per arranged pane below the panes, placed around the pane's layer as
  AppKit placed it (the split's own layer is not geometry-flipped inside the
  flipped page host), and moves it in the split's own layout transitions. A
  lone pane's layer waits hidden, so dividing it animates the shadow with the
  pane. Its image is applied only when the layer is created or the backing
  scale changes.

Checks: `python3 tests/EmptyWindow/check.py` (placeholder color and
accessibility in both appearances, the image's clear continuous-corner
interior, downward offset and fade, the shadow view's input, accessibility and
redraw policy, split backing and shadows through pane arrival and departure,
and unequal stacked panes in a flipped host, with negative controls for each),
`tests/ContentFocusRequest` (the blank tab's focus), plus `tests/SidebarMotion` and
`tests/SidebarPacing`, where the shadow view takes one geometry animation and
no per-frame work.
