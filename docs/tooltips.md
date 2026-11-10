# Tooltips

row of keycaps, drawn in a borderless child window above the control's window.
Any `NSView` opts in by setting `parcTooltip`, and the browser window's
controls do so through `LiveShortcutToolTip` ([adoption](#adoption)). The
SwiftUI `.help` surfaces, menus) or show overflowing content text.

Sources: `Tooltip.swift` (configuration, palette, keycaps, corners, shadows,
timing, eligibility, the presentation state and placement), `TooltipView.swift`
(layout and drawing) and `TooltipController.swift` (the `NSView` property,
the SwiftUI modifier and its anchor view, `LiveShortcutToolTip`, each view's
tracker, the per-window controller and the tooltip window). Parc's extension
controller's timers and tracking areas don't fire, so it presents a disabled
row's reason through `TooltipPresenter` itself, on a common-mode timer with the
controller's stop and idle delays and fade. It reuses one presenter on the same
card, so a tooltip still up or fading moves to the next row at once, as the
controller's does.

## Reference

`4e452201e483b5480c0403a9ef8566e10515cdcb78828622ff9032b202e29547`. All
addresses are 1.122. The evidence came from the annotated-disassembly,
cross-reference and Swift-type helpers; no decompilation was used. The only
read with `assetutil`. Tags: **[D]** disassembly or data, **[M]** Swift type
"Hide sidebar ⌘ S" tooltip, **[C]** measured from the system frameworks on
this OS.


## Using it

```swift
LiveShortcutToolTip.set(button, "Go back", commandID: "goBack:")
view.parcTooltip = TooltipConfiguration("Space 1", anchor: .top)
```

  the label, an optional shortcut, `anchor` (default `.bottomTrailing`),
  `behavior` (default `.onMouseIdle(delay: 0.45)`, or `.immediate`),
  `maxWidth` (nil is 296), `allowedModifierKeys` (default none) and an optional
  `.label(subtitle:)`, [below](#the-label-style), or
  `.dockItem(profileName:)`, [below](#the-dock-item-style)), `requiresShortcut` (no
  in the view's bounds, for a view that draws its tooltipped parts; nil is the
  bounds).
- **SwiftUI controls** take `.parcTooltip(configuration)`, which overlays a
  `TooltipAnchorView` carrying it ([below](#swiftui-controls)).
- **`LiveShortcutToolTip.set(view, title, commandID:, requiresBinding:,
  anchor:, behavior:)`** sets the configuration with `.command(id)` keycaps
  and binds the view's accessibility help ([below](#accessibility-help)).
  no tooltip on.
- **Shortcut.** `.fixed(KeyboardShortcut)` shows that chord.
  `.command(id)` reads the command's live, valid binding each time the tooltip
  is shown, through `TooltipController.commandShortcut`. The app installs that
  as `KeyboardShortcuts.shared.activeShortcut(for:)` beside
  `LiveShortcutToolTip`'s resolver, so the component has no registry
  dependency. A command without a valid binding shows the label alone.
  Pressed keys are matched by `charactersIgnoringModifiers`, which keeps
  Shift. A Shift binding whose key types another character (⇧⌘[ types `{`)
  therefore never shows its key keycap held, and performing it does not
  dismiss the tooltip. The ⌘S pilot is unaffected.
  owns the view's one tooltip tracking area. Changing the configuration reuses
  the tracker and refreshes a shown tooltip; nil removes the tracker and its
- **Palette.** A browser window stores `TooltipColorPalette(theme:)` for its
  Space theme on every palette change
  wins; other windows show the neutral palette.
  tooltips.
- **Component checks.** A check that compiles an adopting file also needs the
  three tooltip sources; `tests/Tooltip/support.py` adds them, with the
  ThemeChromePalette, KeyboardShortcut and ViewDisplayFrameDriver slices a
  check does not already compile (also as a command for shell checks).
- **Views that clear tracking areas.** A view whose `updateTrackingAreas`
  removes every tracking area silently drops the tooltip's, for example
  `SidebarPlusMenu.swift`, `SidebarGroupIconPicker.swift` and
  `SidebarEmojiPicker.swift`. Remove only the view's own areas before such a
  view adopts. None of these has a tooltip.

## The pill


|---|---|---|
| Label | FontSet.label at NSFontManager weight 7, 12 pt, `titleColor`, `frame(minHeight: 28)` | SF Medium 12 |
| Row | `HStack(.center, spacing: 6)`, padding 0/10/0/10, `fixedSize(vertical)`, `frame(maxWidth: maxWidth ?? 296, alignment: .leading)` | same; a wrapped label's pill is as wide as its widest line, leading inside the 296-point frame |
| Background | `RoundedCornersShape` filled with `backgroundColor`; 7 pt above and below when taller than 28 | same |

### The label style

`VStack(alignment: .leading)` with SwiftUI's default spacing of the title,
`lineLimit(4)` in the label font at 12, over the optional subtitle in
the same row, padding and background as standard content.

SwiftUI's default spacing and line heights were measured with
`NSHostingView` on this OS [C]: 0 points between the texts, 15 points per
title line and 14 per subtitle line (each font's whole-point ascent plus
descent). A title over a subtitle is therefore 29 points tall, above the
28-point minimum, and takes the background's 7-point overhang above and below.
Parc's `.label` style draws exactly that: fixed 15- and 14-point lines, the
title truncated on its fourth line, the subtitle in the title colour at 0.66
alpha, both leading, the row as wide as the wider text.

Parc draws in `draw(_:)`. Core Graphics shadows ignore the CTM, so the offset
and blur are mapped to device space. The blur is twice SwiftUI's radius,
outset of three radii covers it).

The layout is aligned to the destination screen's scale before placement. The
label, keycap and glyph origins and the 32.5-point margin round to device
pixels (33 points at 1x), as SwiftUI aligns its frames.

### The dock item style

`AnyView(SidebarDockItemTooltipView(title, profileName, palette))` (metadata
item's optional keyboard shortcut, anchor top and `.onMouseIdle(0.45)`
after the content. `SidebarDockItemView.ViewState.Tooltip` is `{title,
profileName?, keyboardShortcut?}` and `SidebarDockViewController.ViewState`
has `shouldShowProfileInTooltip` [M].

.center, spacing: 6)` of the title in the 12-point label font and `titleColor`,
full size, no chevron, tooltip "Current profile", `onClick` nil [D]. Its theme
draws the icon and name in the palette's `keyTitleColor` over
pressed (`Gray2` at 0.8) colours never apply, because the tooltip window takes
no mouse [D, I].

Parc's `.dockItem(profileName:)` draws that row: the title, 6 points, then a
capsule with the Space header's full-size indicator geometry (5 points leading,
6 trailing, 4 above and below, a 20-point icon slot, 2 points, the name in
11-point medium on its 14-point line), 22 points tall and centred in the
28-point row. The capsule fills with the key face colour, and its icon and name
take the key glyph colour, so they follow the Space theme's palette as the
keycaps do. A long title wraps beside the capsule within 296 points. Without a
Profile the row is the standard pill. The icon is `person.crop.circle`, the

The dock (`SidebarView`) passes the Space's Profile name while the app has more
than one Profile, mirroring `SidebarSpaceState.shouldShowProfileIndicators`,
and `.command(NumberedTarget.spaceBindingID(n))` for the Space's position in
the Spaces menu, so the keycaps show its live Control-digit binding [I: the
producers of `shouldShowProfileInTooltip` and `Item.keyboardShortcut` were not
traced]. The tooltip takes the window's palette. Where
`SidebarDockItemTooltipView`'s palette argument comes from was not traced.

A long Profile name does not push the pill past its 296 points: as the Space
header caps its indicator (at 110 points or half the title's width, tail
truncated), the capsule takes at most half the row's room after its 6-point
distribute the width itself; how it shares it here was not recovered.

### Copy Quote as URL

In quote mode the URL bar's copy button shows custom content,
`VStack(alignment: .center, spacing: 6)` of an `HStack(spacing: 6)` holding
250 points wide at 1200:630 with 5-point continuous corners over a `Gradient2`
Custom content keeps the standard font, colour, 28-point height, padding and

**Excluded: the preview image.** Its URL is
service. Parc does not fetch it and shows neither the image nor its
placeholder. Without it the `VStack` holds only the row, whose infinite-width
label sizes to its text, so Parc's two quote-mode buttons ("Share Quote" and
the quote icon) show the standard pill: "Copy Quote as URL" with
`copyCurrentURLAsQuote:`'s live keycaps (⌃⇧⌘C by default). Their accessibility

### SwiftUI controls

is `content.overlay(Representable?)` [M]. The representable's view,
`ConditionalHitTestView`, stores the configuration through the NSView setter in
only while the controller's `hitTestingView` (field 11, `+0x80` [M]) is this
view, otherwise nil. The controller sets that field around each of its own hit
keeps its clicks, hover and cursor, while the rule that the pointer's hit view
lies inside the tooltipped view still holds.

Parc's `.parcTooltip(_:)` overlays `TooltipAnchorView` the same way (nil
overlays nothing), hidden from accessibility. The controller's
`hitTestingView` is set and cleared around its one hit test helper, which the
entered, pointer-stop, exit and backstop paths all use. Site Control Center's
controls use it: the action buttons (their titles, with
`copyCurrentURL:`, `capturePage:`, `captureVisiblePage:` or
`captureFullPage:` keycaps; Share has none), the extension buttons (the
action's tooltip, else its name), Add Extension, the pin badge (Pin or
Unpin), and in Josh's November 1 restyle the section headers, setting rows,
Secure / Insecure and More. The text SwiftUI's `.help` gave as accessibility
help stays as each control's accessibility hint where its label differs.
restyle's card window takes the window theme's palette instead, because Josh
asked for theme-derived styling throughout it.

## Keycaps


  ⌃ ⌥ ⇧ ⌘, then the key. `HStack(spacing: 3)`, each keycap at least 19 × 19.
- **Base.** `keyBackgroundColor` plus a top-to-bottom clear → black 10%
  gradient, clipped to a continuous radius 4.
- **Face.** A continuous radius 3 in `keyForegroundColor`, inset 1/1/2.5/1.
  The bottom inset is 1 while the key is held, animated `.easeOut(0.12)`.
- **Glyph.** The label font made bold at 10 pt, `keyTitleColor`, 2 pt of
  horizontal padding.
  stores (↩ ⌫ ⎋ ↑), and anything else is the raw key equivalent. Parc takes it
  from the shared key formatter's Essentials keycaps
  (`KeyboardShortcut.keycapSymbols`).
- **Held keys.** While a tooltip is up, key down, key up and flags-changed
  events drive the held faces. A modifier keycap is held while its flag is; the

## Colours

`AppearanceBasedConfiguration<StorableColor>`. Dark Aqua resolves `dark` and

light / dark, extended sRGB [D]:

| Field | Light | Dark |
|---|---|---|
| `titleColor` | black | white |
| `backgroundColor` | white | 0.17 grey |
| `keyForegroundColor` (face) | 0.9 grey | 0.28 grey |
| `keyBackgroundColor` (base and lip) | 0.66 grey | 0.45 grey |
| `keyTitleColor` (glyph) | black | white |

semantic palettes' `appearanceBased(light, dark)` pair (light first, per the
type metadata), and maps each half through `AppearanceBasedConfiguration.map`
`0x10 + 32 × index`:

| Accessor | Offset | Semantic field | Tooltip field (output offset) |
|---|---|---|---|

function reloads the light palette's `+0x110`, `+0xf0` and `+0x70` into both
halves of the three key colours. Title and background keep their split.
`TooltipColorPalette(theme:)` builds the two halves from
`ThemeChromePalette(theme:isDark:)`. A theme with no colour keeps the neutral
palette, because Parc's colourless `ThemeChromePalette` is a system-colour
fallback rather than a semantic palette.

**Base colours.** The semantic palettes blend `shadedDark` over
`+0x10`) [D]. The catalog stores them as static sRGB white (1, 1, 1, 1) and
black (0, 0, 0, 1) with no Dark Aqua variant, so `ThemeChromePalette`'s
white and black hold.

**Appearance follows the app.** `NSWindow.appearanceSource` defaults to NSApp
never sets an appearance [D]. The tooltip window therefore resolves against the
app's appearance, not the browser window's or the sidebar content's. Parc
leaves the window's appearance unset. A light Space theme shows a navy pill
when the app is Dark and a near-white one when it is Light.

dynamic palette colour, then the stroke and the shadows. No opacity, blend,
material or overlay is applied [D]. The only other opacity is the fade's. `StandardTooltipContentView` declares a `colorScheme`
environment value [M] that the content and background builders do not read.

**Reference capture.** [O] is an untagged sRGB JPEG. `NSBitmapImageRep`'s
`colorAt(x:y:)` reads such a file as gamma-1.8 RGB, so its stored bytes must be
measured directly. Its theme is not recoverable, but a Display P3 primary,
builds primaries in Display P3 HSL
([theme input](space-theme-input.md)):

| | Capture (stored sRGB) | Parc, fitted theme, app Dark |
|---|---|---|
| Pill | (3, 28, 50) | (0, 27, 51) |
| Key face | (187, 220, 238) | (196, 222, 238) |
| Lip luma | ≈150 | ≈158 |
| Glyph luma | ≈76 (darkest pixel of a thin stroke) | 73 |
| Label luma | 214–224 | 225 |

The capture's glyphs look darker teal than Parc's (0, 91, 168) only through
JPEG chroma averaging on thin strokes. The best plain sRGB primary fits worse,
because its face red cannot fall below 204. The fitted colour is an estimate,
not the user's theme.

## Window and placement


- A borderless, buffered, clear, non-opaque window that ignores mouse events
  and is not released when closed. It never becomes key or main. Parc also
  hides it from accessibility, as a help tag is.
- It is added as a child above the anchor's window at level 24 + 1.
- Its frame is the tooltip frame outset by the largest offset plus three times

space against the anchor's bounds in window coordinates:

  the screen holding most of the anchor, falling back to the window's. A
  window spanning displays with separate Spaces off then still shows a
  control's tooltip on the minority display.
- **Edge anchors.** Top and bottom centre horizontally with a 4-point gap,
  Leading and trailing centre vertically, 4 points away.
- **Diagonal anchors** overlap the anchor's corner by 6 points; bottomTrailing
  is (maxX − 6, maxY − 6).
- **Cursor** is 12 points right of and below the pointer.
- **Fallback.** The preferred anchor is used when its frame lies on the screen.
  Otherwise the fitting candidate (the eight edges, then the cursor) nearest
  viable frame to present tooltip." and shows nothing.

## Motion and the controller

holds its rules apart from AppKit; `TooltipController` runs the tracking areas,
timers, hit tests and window those rules name.

- **Entering.** Only a view the pointer actually reaches gets a tooltip
  only views hit on entry; Parc records every entered view and applies the hit
  test when scheduling (on entry and when the pointer stops), so a view that
  takes the pointer over only part of its bounds, such as the Library entry's
  canvas, gets its tooltip once the pointer reaches that part.
- **Idle.** Movement cancels a pending tooltip. A stop (0.08 s after the last
  move) schedules the innermost entered view under the pointer. An idle
  tooltip shows its delay after that, so 0.45 s means about 0.53 s
  0.01 s.
- **Warm handoff.** While a tooltip is up or still fading, another
  view-anchored one replaces it at once in the same window, fading from its
  current opacity to 1. A cursor-anchored one waits.
  tooltip is pending hands off to the innermost enclosing tooltipped view
  under the pointer. Leaving a shown one for a view-anchored enclosing view
  hands off warm. For a cursor-anchored enclosing view (a tab row, after its
  fade.
  or while `+[NSEvent modifierFlags] & ~allowedModifierKeys` is non-zero. The
- **Showing.** Opacity animates from the presented value to 1 over 0.05 s,
  that value is never seen; Parc omits it. A warm handoff fades up from the
  fading value.
  drops only entered views whose visible rect no longer holds the pointer,
  so a view the pointer is still inside, where it passes the pointer
  through, is scheduled again once the pointer stops on its part.
- **Hiding.** Opacity fades to 0 over 0.3 s, or 0.1 s for a cursor tooltip's
  resigning key fades 0.3 s. Performing the shown shortcut fades 0.3 s after
  them. A scroll leaves no warm state for cursor tooltips. A fade's window
  tracks each animation, so a second dismissal during a fade fades on from
  the current opacity rather than closing at once.

## Parc choices

These fill gaps the reference leaves open:

1. **Drawing.** AppKit drawing replaces SwiftUI. SwiftUI shadow radius is
   taken as the Gaussian's standard deviation.
2. **Corner style.** The pill's corners are circular arcs, because
   Keycaps are continuous, as recovered.
3. **Colourless themes** use the neutral palette, and every themed palette
   (non-appearance-based) semantic palette.
   F-key's raw key equivalent; Parc's shared formatter names it (F21). Return,
5. **Pointer moves** come from the tooltip tracking area's mouse-moved
   events, not a separate monitor, so the window needs no
   `acceptsMouseMovedEvents`. A mouse-moved event has no tracking area
   (`NSEvent.trackingArea` raises "Invalid message sent to event" on one), so
   it routes by its window. Entered and exited name the tracker's own view.
   The tracking area is active in every window state; eligibility decides.
   One stop timer moves its fire date on each move.
6. **Dismiss and key monitor.** It runs only while the pointer is over a
   tooltipped view or a tooltip is scheduled or up. Hovered views that went
   away, left the window or were hidden without an exit are dropped first, and
   every handled event re-checks, so the monitor retires. A dismissal with
   nothing scheduled or shown changes nothing, so a stray click does not warm
   cursor tooltips.
7. **Pressed state.** Pressed characters are `charactersIgnoringModifiers`, and
   held modifiers are seeded when a tooltip first shows.
8. **Rebinding while shown.** A live binding changed while its tooltip is
   visible appears at the next show. A view's configuration changed while
   its tooltip shows replaces it only while the pointer is still over the
   view; otherwise the tooltip hides, so a view that resets its tooltip as
   the pointer leaves (the Library entry) never flashes the reset one.
9. **Window close.** The tooltip closes at once when its parent window closes.
10. **Hidden behaviours kept literal.** Fallback candidates include the cursor
    (contract open question). Reduce Motion does not change the fade or the

## Adoption

its 26 SwiftUI `View.help` sites and its `setToolTip:` senders. The map, with
`work/cursor-tooltip-research/adoption-map.md` (beside the call-site
inventory `rea/inventory.tsv` and the helper outputs `rea/sites.tsv` and
`rea/shortcuts.tsv`). In short:

- **Converted** (57 controls): the sidebar header and toggle, the address
  pill's Site Control Center, quote and payment buttons, tab rows and their
  Close, mute, share, capture and Reset controls, Clear, the dock's Spaces,
  the Library entry, the Space header's profile and Incognito indicators, split
  the command bar's Delete Suggestion, mini players, Space management and
  creation, the theme editor, Portrait capture, the Library's archive row,
  Downloads filter and More buttons, Easels & Notes' New Note, extension
  buttons, the extension side panel's Close and Site Control Center's
  anchors and delays replace Parc's where recovered: for example "Archive this
  "Back to Tab", "Toggle Camera", "Hide Watermark", "Copy Quote as URL", dock
  items above with their Profile ([dock item style](#the-dock-item-style)),
  Remove Filter after 0.6 s.
- **New** (4): Exit Library, a rail tile's title while its slot is too short
  buttons and its noise control.
  `plusButtonView`) and the URL pill's address button, which keeps its
  accessibility help.
- **Help only**: the New Tab row already had no tooltip (`NewTabCellState`
  has none). It gains "New tab" with New Tab's binding
  (`NewTabCellState.newTabShortcut`) as accessibility help.
  `View.help`), Easel (its own EaselUI tooltip path), Notes, system menu items
  (the extension menu's rows use Parc's tooltip), and
  overflowing content or status text.
  ([Copy Quote as URL](#copy-quote-as-url)).

The Space theme editor's tooltips leave `palette` nil, so they take the
popover window's palette, which the window owner sets from the edited theme
`knobRect`), following the dial's frame. The whole 80-point dial still
triggers it, because the controller has no hit region smaller than a view.

### Tab rows

`TabCellState.tooltip` is a `TooltipViewModel` {title, subtitle?, anchor,
`.spaces` (`SidebarSpaceState.windowLayoutPresentation`, the byte after its
16-byte `windowID`), which Parc always is; the title from
`SidebarTabTitle.display` follows; the subtitle "Double-click to rename"
`+0x18` of the class instance) is nil; anchor 8 (cursor) and delay 1.5

passes each press's click count to the window store, and the state carries
the edited item (`SidebarSpaceState.editingItem`, `WindowAction.setEditingItem`).
from the ordinary inline editing-ID path" ([saved tabs](saved-tabs.md)); the
reducer branch that turns an ordinary row's double-click into that action was
not located with the helpers [I]. Parc's row begins its title editing on the
second click of a plain (unmodified) double-click on the row body, through
the same lease as the context menu's Rename. Its buttons and reset region
take their own presses, a press that became a drag never reaches it, and the
first click still selects. The hint shows exactly where that rename applies:
a tab `SidebarTabTitle.isRenameable` admits (not a Favorite, not an Easel or
Note page) outside Space management. The live lease is checked at the click.
A split child is not a tab cell: `SplitViewCellState.ChildItemState` has no
[navigation](navigation.md)). Parc's split children show no row tooltip and
do not rename on a double-click; the separation is the split family's.
`SidebarSpaceState.renameHintItemID`) is not part of the tooltip, which

read as the model being absent [I]. No path that drops the tooltip during
editing was found, and none was confirmed at runtime. Parc keeps the row's
tooltip while its title field edits.

### Accessibility help

A help tag was also the control's accessibility help. `LiveShortcutToolTip`
keeps it: the app installs `KeyboardShortcuts.bindHelp` as the binder, which
sets the title and the command's current valid binding ("Go back ⌘[") as the
help of the view and, for an `NSControl`, of the cell AppKit exposes, and
refreshes it on every binding change, clear, conflict or reset. The help is
spoken, so it says Space where the keycap shows ⎵ (`spokenDisplay`). A
binding-only control (Reset Tab) has no help while unbound. Without a binder
the help is the title. Controls that set their own help (for example the tab
row's URL and the theme noise dial) or whose label already says the same (for
example dock items and appearance buttons) set `parcTooltip` directly.


## Checks

`tests/Tooltip/check.py` is in `scripts/test.sh`. It compiles the three
sources with `SpaceTheme`, `ThemeChromePalette`, `KeyboardShortcut` and
`ViewDisplayFrameDriver` and checks:

- the configuration defaults, including style, binding requirement and anchor
  rect;
- the neutral and theme palettes, including key colours from the light palette
  in both appearances and preserved wide-gamut components;
- keycap order, glyph mapping and held state;
- per-anchor corners and the capsule;
- every anchor's origin, clamping, the clamp region and screen conversion,
  fallback, no fit, and the screen holding the anchor;
- layout (28-point row, 19-point keycaps, 6/3/10 spacing, pixel rounding and
  pixel-aligned origins and margin, wider glyphs, wrapping within 296 or a
  custom width) and the label style (15- and 14-point lines 0 apart, the
  29-point two-line row, centring without a subtitle, the four-line cap);
- offscreen drawing (fill, face, lip, light and dark border, shadows, clear
  margin, the held face, the label style's 7-point overhang and 0.66 subtitle);
- the dock item style: the capsule 6 points after the title, 5 / 20 / 2 /
  name / 6 wide and 22 tall on the name's 14-point line, centred in the
  28-point row, the keycaps after it, the standard pill without a Profile, a
  long title wrapping beside it, and the capsule drawn in the key face colour
  with its icon and name in the key glyph colour; a long Profile name capped at
  half the row's room and tail-truncated, keeping the title's width, the pill
  within 296 points and the capsule's trailing padding clear;
- eligibility, including Caps Lock;
- the presentation state: idle scheduling and movement, presentation, warm
  handoff while shown and while fading, fades that keep or close the window,
  dismissal bookkeeping, scroll, cursor warm delay, immediate tooltips, exit
  hand-off and durations, a shown child that hides rather than handing off to
  a cursor-anchored row (declined during the fade, scheduled after it) while a
  pending one hands off, shortcut and Escape dismissal, and failure;
- the `parcTooltip` property's help-tag and tracking-area handling, and
  `LiveShortcutToolTip`: the pill with `.command` keycaps and no help tag, the
  title as help on the button and its cell without a binder, a site's anchor
  and delay, a binding-only tooltip, the app's binder, and help alone;
- real `NSEvent`s through a view's own tracking-area owner, on windows that
  are never ordered in (their tooltip child stays off screen with them). The
  held modifiers, mouse buttons and pointer the controller reads are the
  test's own (`InputOverrides` in `tests/Support/AppKitObservation.swift` and
  the stand-in windows), so a person using the machine does not change the
  outcome; a held modifier declines a tooltip. An entered event shows the
  tooltip after 0.45 s. A mouse-moved event reaches
  the controller and cancels a pending tooltip. A second dismissal keeps
  fading and the latest fade closes the window. A binding-only tooltip shows
  only once its command has a binding. A view that takes the pointer over one
  part shows nothing when entered elsewhere and anchors to the part's rect;
  entered elsewhere, it shows once the pointer moves onto the part and stops,
  and after the backstop hides it in a gap inside the view, stopping on the
  part again shows it. A configuration changed while shown replaces the
  content with the pointer over the view; with the pointer gone it leaves the
  content and the window fades and closes.
  The tooltip window never takes key, main, the mouse or accessibility.
  Nothing is logged as "Invalid message sent to event";
- the SwiftUI bridge: `.parcTooltip` on a SwiftUI button in an
  `NSHostingView` overlays one anchor covering the button; an ordinary hit
  test at its centre passes through to the hosting view; a real entered event
  through the anchor's tracking owner shows its tooltip after 0.45 s, with the
  controller's `hitTestingView` cleared again; nothing is clicked or shown;
  and a nil configuration removes the anchor;
- by source text: the adoption's wiring (the toggle, row Close and row
  tooltips, Reset Tab, dock items with their Profile and numbered binding, the
  quote buttons' "Copy Quote as URL", Site Control Center's bridged
  controls and no SwiftUI `.help` there, rail tiles, Exit Library, Remove Filter,
  tag left in the converted files, the Library entry without its own panel,
  the registry binding help rather than help tags, the tooltip window's
  guarantees, no key, main, front-ordering or activation call in the tooltip
  sources, and no `event.trackingArea` read.

The adopting views' own checks (Library entry, popup chrome, live bindings,
split, mini player, toolbar and Library checks) assert their configurations
and help through `parcTooltip`. The theme input check anchors "Noise" below
the dial's knob as its frame changes and finds no editor tooltip with its own
palette. The Space manager check renders a real sidebar
and checks the row tooltips (an unrenamed pinned or Today row's hint, a
renamed row's custom title, a document row and a Space card's row without
it), the deselect and archive Close tooltips, and the row body's
double-click: a single click selects, a modified double-click does nothing,
and a plain one begins the rename without selecting again. The Site Control
Center check hosts the real view in a window that is never shown and finds an
anchor on every action, extension, the pin badge, Add Extension and the
restyle's other items, with the actions' commands, no palette of their own (so
the card window's themed one) and ordinary hit tests passing through each.

`tests/Tooltip/support.py` gives a component check the tooltip sources it
needs. It stops with the file and marker named when a slice marker it cuts
on is gone.

Routing `mouseMoved` through `trackingArea` again or dropping the
per-animation check each fails it. It never shows a window, makes one key or
activates; a stand-in window reports itself key. The live tracking areas,
local event monitor and on-screen window run only in the app; no functional
browser test was run.
