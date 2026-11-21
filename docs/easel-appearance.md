# Easel static appearance

The Easel shares the original document, text editor and embedded-page owners.
It wears the Notes look: the pane shows the Space theme through the Notes paper,
so an Easel takes the Space's gradient, grain and light or dark exactly as a
note does. Ink, placeholders, selection, guides and floating controls come from
`NoteTheme` through `EaselAppearance`: selection, handles and the marquee use
the Notes accent, alignment guides use tertiary ink, link and webpage cards use
the Notes panel fill. Only corner resize marks are painted; all eligible edge
resize targets retain their native pointer and accessibility actions. A hovered
corner handle grows on the Notes highlight spring ([motion](easel-motion.md)).

## First run

An empty Easel greets you on the paper, 40 points in from the top left: "A
place for your ideas" in Nunito ExtraBold with the Notes title placeholder ink,
one line of Notes placeholder text, then a row of Notes-style chips that teach
the keys (Sticky S, Shape R or O, Connector X, Text T, Draw M, Find anything
⌘/). Each chip draws its keys as Notes keycaps beside a secondary-ink label,
shows the Notes hover and pressed washes and the pointing hand, carries a
tooltip with its shortcut and is a VoiceOver button; clicking one picks that
tool, or opens Find anything. The key labels come from the Easel key map, so
they follow any rebinding, and Find anything only appears where ⌘/ works.
Under the chips, "Or start from a template" heads the template gallery's card
row ([templates](easel-board-features.md#templates)); the Easel editor hands
its one `EaselTemplateGallery` to the canvas as an `EaselEmptyStateRow`, the
card plates line up with the words, and the row drops to fewer columns when the
view is narrow or zoomed in. It also shows only the rows that fit between the
words and the floating tool bar, so a short window or split never leaves a card
half under the bar; with no room for a row the heading goes too, and every
template stays a click away in the tool bar. Easel blocks in notes show the words and chips
only. The whole group lives on the canvas, so it zooms and scrolls with the
paper and follows light and dark, and only its chips and cards take clicks:
clicking anywhere else places or selects as usual. It fades and rises 4 points
in like a Notes block, fades out as the first object pops in (a picked template
pops in the same way) and comes back if the board is emptied.

The first time someone selects a single sticky or shape outside the capture
editor, a Notes menu-card chip pops in at the bottom centre of the canvas:
"Tip: click a + beside it to make the next one, or press ⌘Return". It is
announced to VoiceOver, ignores the pointer, leaves when the selection changes,
on any press or after eight seconds, and never shows again
(`easel.quickCreateHintSeen` in user defaults, like the Make it Live education).

The selection toolbar is the Notes format bar's card: a 36-point menu card with
28-point Notes toolbar buttons, one-point spacing and hairline dividers between
groups. It floats eight points above the selection's bounds, centred on the
visible part of them, and drops eight points below when there is no room
above. A selection too tall for either moves it to the top or bottom edge of
the view, beside the selection or in a free strip, whichever covers the least;
only a selection filling the whole view gets it over the top, pinned top centre.
`EaselSelectionToolbarPlacement` in ParcCore owns that choice. It lives in a pass-through layer above the canvas's scroll view
instead of inside the magnified canvas, so it keeps its screen size at every
zoom, follows scrolling and zooming, and stays inside the canvas viewport. Its
controls follow the selection. Text gets typeface and size menus, smaller and
bigger steps, the style button, text fill, alignment and Link; while text is
being edited, text, stickies, shapes and tables add bold, italic, underline,
strikethrough and the paragraph menu, and size controls act on the selected
range. Shapes lead with the shape picker (all 32 shapes, the current one
checked), stickies offer wide or square, connectors offer a label, start and
end heads with Swap Ends, and straight, elbow or curved routing with Reset
Path. Sections get Rename, images crop, mask, replace and alt text, washi tape
its pattern, icon stamps the style button (emoji and built-in stamps keep
their own colours), code blocks their language, and tables typeface, size, bold,
strike, text and cell colour, alignment and merge. The style button shows the
current colour (a dashed ring when they differ) and opens the Easel style
picker with colour, custom hex and sampler, then fill and fill opacity,
outline or line width, dash and a connector's label background, as the
selection allows; while typing it colours the selected text. Alignment and
table text colour show the current value, Mixed when cells or objects differ,
and the alignment menu lists ⌥⌘L, ⌥⌘T and ⌥⌘R, which reach table cells too.
Several objects add align and distribute, tidy up, group, create section and
lock; a locked selection shows Locked with Unlock, or Unlock Group when every
object belongs to one group. A ••• button ends every toolbar with the four
layer moves, Flip Horizontal (⇧H), Flip Vertical (⇧V), Rotate 90° Left and
Right, Duplicate, Copy as Image, Lock and Delete, plus a section's Lock All,
Lock Background Only, Hide Contents and Delete Section Only. VoiceOver
reaches the toolbar right after the selected object. Its buttons never take keyboard focus from a click, so
formatting never ends text editing. Menus are Notes menus opened under their
button that close on a pick, Escape or an outside click; the style picker
stays open so colour, fill and line can be tuned in one visit. Every button calls a
canvas command, so the toolbar, the Format menu and shortcuts make the same
change as one Undo step, and a closed or deleted Easel refuses them. The
original text storage, glyph layout, fill contour, typing history and document
transactions remain the only text owners.

The floating tool bar is the Notes format bar: a 36-point Notes menu
card with its hairline and shadow, holding 28-point Notes toolbar buttons
grouped as navigation, objects, tools, inserts and zoom, with hairline dividers
between groups ([tools and navigation](easel-tools.md) lists the slots). Buttons
use the Notes button states: secondary ink at rest, hover and pressed washes,
a sliding checked pill and checked ink for the current tool, the checked fill for an open picker; variant
buttons carry the Notes disclosure chevron, and the zoom slot shows its
percentage in the Notes chrome font. It floats centred at the bottom of the Easel. The title is
Nunito ExtraBold in the Notes title ink over a caption-style status line. Undo
and redo are 28-point Notes chrome buttons on the title row, with Parc
tooltips showing ⌘Z and ⇧⌘Z as keycaps; shape picker cells, its pin, template
cards, the Mermaid sheet's Add, the empty Easel's chips (in Easels inside
notes too), the timer button (a fixed “Timer”, since the countdown shows on
the button) and the web card's address header use the same tooltips instead of
system ones. The ••• button ends
that row; it opens the [page menu](easels.md#page-menu-and-exports). The toolbar
follows the canvas's current tool and scrolls horizontally when the window is
narrower than the controls. Its explicit overlay scrollbar preserves the full
control height even under the system legacy-scrollbar preference. Placement
ghosts are dashed outlines in the Notes accent over a 10% accent wash, and the
Recenter chip is a filled Notes chip. The ordinary Add Link action now presents the existing
window-owned URL editor, with a compact address-only layout. Its original
owner/visibility/IME/cancellation gates also cover this presentation. The rich
range-link editor retains its separate original-range/revision guard. Both use
plain controls, eight-point corners, semantic outlines and visible invalid-URL
feedback; no browser page is created by either editor itself.

## Ink and saved colours

Objects store colours as RGB hex, and `#252525`, the colour every new object
has always been given, is the automatic ink token. On an Easel canvas it draws
as the Notes ink, dark on light paper and near-white on dark paper, for text,
strokes, arrows and shape outlines. Saved Easels need no rewrite: their default
objects and default-coloured text runs read the same token.

The palette (`EaselPalette`) is Notes' nine colours, gray to red, in four
roles. Every palette colour is stored as its light value and draws its dark
variant on dark paper, exactly like the ink token:

| Role | Used for | Light paper | Dark paper |
| --- | --- | --- | --- |
| Ink | text, arrows, pen, outlines, section titles | Notes text colours | Notes dark text colours |
| Fill | shape fills, section bodies | Notes background colour, 20% over white, opaque | dark background colour, 30% over a dark base |
| Sticky | sticky paper | the same at 42% | 45% |
| Highlight | highlighter strokes, drawn at 35% opacity | Notes background colours, without brown | Notes dark background colours |

Ink offers Default (the token) and the nine; fill and sticky offer White, which
turns into the Notes panel colour on dark paper (the picker and context menu
call it Black there), and the nine. A hex adapts only in its own role: a fill colour used as
ink, a custom colour or any other hex stays exactly as saved. Rich-text runs
adapt the same way, and editing stores the light value again, so a document
stays the same on disk whichever appearance edited it. Default text reads at
4.5:1 or better on every fill and sticky paper in both appearances. Solid fills
are opaque pastels, so shapes and stickies stack like paper. Transparent is the
classic tint: a shape with no saved fill keeps the 9% wash of its outline
colour, and the opacity slider strengthens whichever fill the shape has.

Unset widths keep today's look: 2.5-point outlines, 3-point arrows and pen
lines, 16-point highlighter. Thin, Medium and Thick are 1.5/2.5/5 for outlines
(plus None), 1.5/3/6 for arrows and the pen, and 10/16/24 for the highlighter;
arrows and drawings never drop below one point. Dashes and dots scale with the
width, and arrowheads stay solid and grow with the line.

The style picker (`EaselColorPicker`) is a Notes floating-panel card with the
Notes highlight and press motion: Color swatches, a custom colour from a hex
code (type # to start one) or the screen eyedropper, then Fill (No Fill,
Transparent, Solid and an opacity slider) and Outline or Line (weights, solid,
dashed, dotted) when the selection takes them; connectors add a Label
Background toggle. Text shows colour only, shapes
everything, arrows colour, width and style, the pen and highlighter colour and
width, stickies and sections colour only. The object context menu offers the
same choices as Color, Fill and Outline or Line submenus. Canvas commands (`applyColor`,
`applyFill`, `applyFillOpacity`, `applyStrokeWeight`, `applyStrokeDash`) change
the selection as one Undo step, skip locked objects and kinds a property doesn't
fit, and override every colour in a mixed selection. While text
is being edited, a colour goes to the selected text, or to what you type next
at a caret. Washi tape takes Default (its own design colours) or a Notes colour
that retints the design.
A colour on a shape sets its outline and, when it has a solid fill, the
matching pastel; Default gives a solid shape the automatic ink and a White
fill. Stickies take paper and keep automatic text; sections take a pastel body
and the matching ink for border and title, and Default takes either back to its
plain look.

Applying a style makes it that tool's next default. Shapes, pen,
highlighter, tape, text and sections remember across launches; sticky paper starts
on a random Notes colour each session, then follows the last sticky colour;
connectors remember their colour, width, dash and label background per Easel
until Parc quits.

Copy and image files for other apps keep the stored light colours (copied text
writes `#252525` for the token). Image export paints white or black behind the
objects from the Easel's own appearance and draws in it, so a dark Easel
exports dark variants. HTML export writes palette colours as CSS variables such
as `--easel-ink-blue`, with the light value as fallback and dark overrides
under `prefers-color-scheme: dark`, beside `--easel-ink`. The capture editor
turns adaptive ink off: its annotations are burned into pixels, so they keep
fixed colours and its colour well. Authored font geometry, text fill and
immutable capture pixels are unchanged.

## Native adaptations and boundaries

Document paper, title ink and floating controls resolve from the enclosing
Space `contentOverBackgroundAppearance`, the same Aqua/DarkAqua override Notes
inherit.

The toolbar's typeface, size, paragraph and ••• menus are Notes menu lists, its
style and shape pickers the Easel pickers in a Notes popover,
rather than native pop-up buttons, and its buttons draw SF Symbols or letter
glyphs. Selected/pressed/disabled washes and native focus
rings are explicit AppKit feedback adaptations; their drawing never changes
logical state. The rich-link editor's Remove/Apply actions and the webpage
Address/Search controls retain their existing semantic layout. These are
native presentation choices.

The focus/geometry action owners and shared annotation
eligibility predicates are integrated at drawing, hit admission, cursor
regions, accessibility child creation and retained-action revalidation. Native
motion visibility, Reduce Motion and original-owner cancellation remain owned
by `EaselMotion`. Embedded live-page crop/mask/loading pixels and beforeunload
retirement remain owned by the delivered page pool. No engine change is needed.

The windowless `EaselInkTests`, `EaselPaletteTests` and `EaselStyleTests`
suites in `tests/NotesEditor` check ink and palette resolution, contrast, chosen
colours, token round trips, style commands and remembered styles;
`EaselSelectionToolbarTests` checks which controls each selection gets. Inert
checks cover all font/fill/history behavior, the toolbar's text state helpers,
non-overlapping controls, actual selected/disabled states, light/dark drawing,
unchanged attributed text, scaled corner/edge admission, retained edge refusal after zoom, narrow toolbar
content height under legacy preferences and the compact native
URL editor. Shared Notes and capture editor checks exercise the reused classes.
