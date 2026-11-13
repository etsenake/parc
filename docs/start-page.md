# Start page

A Space with no open tab gets a start page: the Parc mark above a resident
command bar, on the Space's own colors. It replaces the "No tab open"
placeholder and retires the rule that keeps the sidebar out in an empty window,
so Command-S hides the sidebar there like anywhere else. The open item is in the
[backlog](backlog.md#planned-interface-work).

## Today

- An ordinary window whose Space has no selected item shows
  `SplitPanePlaceholder`, a translucent card reading "No tab open" that takes no
  input. See [window appearance](window-appearance.md#a-window-with-no-tab).
- `EmptyWindowSidebarRule` in
  [SidebarMotionController.swift](../Sources/ParcApp/SidebarMotionController.swift)
  keeps the sidebar out: a request to hide it yields the floating sidebar, and
  closing the last tab floats a hidden sidebar. Command-S therefore can't hide
  [sidebar motion](sidebar-motion.md#a-window-with-no-tab-keeps-its-sidebar).
- Add Split's pending pane counts as empty under the same rule.

## Reference: Dia's empty Space

- The window fills edge to edge with a dark vertical gradient in the profile's
  color, with no page card.
- Dia's logo, about 65 points wide and tinted in that color with a brushed
  texture, sits about 24 points above a 565-point rounded input card. The pair
  sits a little above the window's center.
- Typing grows the card downward with suggestion rows while its top edge stays put.
- Sidebar, Back, Forward and Reload buttons sit in the top-left corner.

## When it shows

The start page shows when an ordinary or private window's current Space has no
selected tab, Note, Easel or split, including in full screen. Closing the last
open tab in a Space, by Command-W, its close button or a closing command, opens
the start page in that window with the command bar focused and ready to type;
the window stays open. Switching to a Space with no open tab, or creating one,
lands there too. Popup windows, an open Library and Space creation keep their
own content. Add Split's pending pane keeps today's placeholder and sidebar hold
while a result is being chosen.

## Sidebar

- Retire the no-tab half of `EmptyWindowSidebarRule`. Command-S toggles docked
  and hidden in an empty Space, closing the last tab leaves the sidebar where it
  was, and the left edge reveals the floating sidebar on hover as usual.
- With the sidebar hidden, the start page shows the window controls and a
  sidebar button in the top-left corner, so the window can always be closed and
  the sidebar found. Its background drags the window like the sidebar background.
- The rule retires in the same change that ships the start page, because the
  start page's command bar is what replaces the sidebar as the way out of an
  empty Space.

## Command bar

The input is the command bar itself, not a new search box: the same native
suggestions, open-tab switching, application commands, Type Travel, website
scopes and Tab-to-search as Command-T.

- At rest only the field shows. Typing grows results downward in place with
  the top edge fixed, up to the palette's five visible rows.
- Submitting a navigation opens a new tab in this Space, exactly as Command-T
  does. Switch-to-tab rows and commands behave as in the palette.
- Escape clears the query and collapses the results; it never dismisses the page.
- Command-T and Command-L focus the resident bar instead of stacking a palette
  over it.
- The field takes focus when the start page appears in the key window, unless
  another control already holds it, following the existing content-focus rules.
- It is a resident presentation of the existing command bar session, hosted in
  the page area instead of the window overlay host. Result ownership, ranking
  and submission stay unchanged; `CommandBarAppearance` supplies its palette
  over the Space's content appearance. Width is the palette's 765-point maximum
  or narrower, settled in review.

## Background

- The Space's full theme: every color combined by the existing theme renderer
  exactly as the window gradient draws them, with the theme's intensity, in its
  light or dark content appearance. No texture by default; the review compares
  it with texture.
- It shares the window's gradient coordinate space, so it lines up with the
  frame and the floating sidebar, and it takes part in Space paging, so swiping
  between an empty Space and a busy one blends both themes.
- Private windows use the private palette. Themes without color fall back to
  material like every other theme surface.
- The page card stays by default: the [window frame](window-frame.md) setting
  still applies, and opening a tab swaps the card's content without a layout
  jump. The card holds the untextured gradient, so the textured frame reads as
  a border around it. Dia's edge-to-edge fill is the review alternative.

## The mark

- Parc's mark from `ParcBrandMark`, sized and spaced close to Dia's: about 65
  points, about 24 points above the bar, the pair a little above center.
- Default treatment: the monochrome mark's shape filled with the Space gradient
  and keeping the theme's texture, so the mark is the one textured thing on the
  page. The color mark is the alternative.
- It is decorative for accessibility, and nothing depends on it.

## Easter egg

Interacting with the mark in one deliberate way plays a playful, Browser
Company-spirited animation: tactile, colorful, physics-driven, surprising the
first time and never in the way. Candidates for review:

1. **Taffy.** Press and drag the mark: it stretches on a spring and, released,
   snaps home with a wobble and a haptic tick.
   trailing a ribbon in the Space's colors, landing with squash and stretch.
3. **Charge-up.** Press and hold: the mark squishes and glows in the theme's
   colors; let go and it loops the loop, dusting the page with theme-colored
   confetti.

- A single click does nothing, so it never fires by accident. Each trigger
  plays once, and triggers don't stack.
- Nothing animates at rest. Hidden, occluded and miniaturized windows pause.
- Reduce Motion replaces motion with a short shimmer through the theme colors.
- Sound and haptics follow Parc's existing interface feedback preferences.

## Transitions

Closing the last tab fades its page out and the start page in, within the same
card, and the command bar takes focus as it arrives. Opening a tab from the bar
reverses it. Reduce Motion crossfades.

## Visual review is required

Design this through the [interface review](visual-review.md) workflow, renders
first, and approve the direction before building:

- empty Spaces in single-color, multi-color, light, dark, colorless and private
  themes, at rest, while typing and with results;
- docked and hidden sidebar, at the default, thinnest and thickest frame;
- page card against edge to edge, texture on and off, both mark treatments;
- each Easter egg candidate as an animated mockup, plus its Reduce Motion form.

The live look-and-feel pass in Parc follows that guide's runtime boundary.

## Build order and checks

1. Start page with the resident command bar and theme background, retiring the
   no-tab sidebar rule in the same change.
2. The mark and its Easter egg.

Checks: model tests for the empty-Space condition and sidebar toggling
(Command-S hides in an empty Space, closing the last tab shows the start page
with the field focused and keeps the sidebar presentation, Add Split still holds), resident command bar tests (Escape, Command-T focus,
submission opens a tab in the Space), theme surface tests (texture off, shared
coordinate space, paging), Swift typecheck and whole-module SIL. No engine
change is needed. When it ships, update the empty-window sections of
[window appearance](window-appearance.md) and [sidebar motion](sidebar-motion.md)
and the command bar's entry points.
