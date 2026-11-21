# Easel static appearance

The Easel shares the original document, text editor and embedded-page owners.
It wears the Notes look: the pane shows the Space theme through the Notes paper,
so an Easel takes the Space's gradient, grain and light or dark exactly as a
note does. Ink, placeholders, selection, guides and floating controls come from
`NoteTheme` through `EaselAppearance`: selection, handles and the marquee use
the Notes accent, alignment guides use tertiary ink, link and webpage cards use
the Notes panel fill, and the empty-Easel prompt uses the Notes placeholder inks
in Nunito. Only corner resize marks are painted; all eligible edge resize
targets retain their native pointer and accessibility actions.

The selection toolbar is the Notes format bar's card: a 36-point menu card with
28-point Notes toolbar buttons, one-point spacing and hairline dividers between
groups. It floats eight points above the selection's bounds, centred on them,
drops below when there is no room above and pins to the top of the view only
when the selection is taller than the view, so it never covers what it edits
otherwise. It lives in a pass-through layer above the canvas's scroll view
instead of inside the magnified canvas, so it keeps its screen size at every
zoom, follows scrolling and zooming, and stays inside the canvas viewport. For
text it offers the typeface and size menus, smaller and bigger steps and the
text-fill toggle; while text is being edited the steppers give way to bold,
italic, underline, strikethrough, the paragraph menu and Link, all acting on
the selected range. A ••• button ends every toolbar with Bring to Front,
Duplicate and Delete. Its buttons never take keyboard focus from a click, so
formatting never ends text editing. Menus are Notes menus opened under their
button that close on a pick, Escape or an outside click. Every button calls a
canvas command, so the toolbar, the Format menu and shortcuts make the same
change as one Undo step, and a closed or deleted Easel refuses them. The
original text storage, glyph layout, fill contour, typing history and document
transactions remain the only text owners.

The tool strip is the Notes format bar: a 36-point Notes menu card with its
hairline and shadow, holding seven icon-only 28-point tools in
select / image / text / circle / square / arrow / scribble order. Tools use the
Notes button states: secondary ink at rest, hover and pressed washes, and the
checked fill and ink for the current tool. It sits centered under the title,
which is Nunito ExtraBold in the Notes title ink over a caption-style status
line. Link, webpage, undo and redo are 28-point Notes chrome buttons on the
title row so those actions remain reachable without joining the strip. The ••• button ends that
row; it opens the [page menu](easels.md#page-menu-and-exports). The strip still follows the actual drawing mode and
scrolls horizontally when the window is narrower than the controls. Its explicit overlay scrollbar preserves the full control
height even under the system legacy-scrollbar preference. The ordinary Add Link action now presents the existing
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
objects and default-coloured text runs read the same token. Editing stores the
token again, never the resolved light or dark value, so a document stays the
same on disk whichever appearance it was edited in. Any other colour is a
chosen colour and stays exactly as saved. Copy and export to other apps write
the fixed `#252525`, so pasted text stays readable on their white pages.

The capture editor turns adaptive ink off: its annotations are burned into
pixels, so they keep the fixed colour and its colour well. Image export paints
white or black behind the objects from the Easel's own appearance, matching the
ink it draws with. Authored font geometry, text fill and immutable capture
pixels are unchanged.

## Native adaptations and boundaries

Document paper, title ink and floating controls resolve from the enclosing
Space `contentOverBackgroundAppearance`, the same Aqua/DarkAqua override Notes
inherit.

The toolbar's typeface, size, paragraph and ••• menus are Notes menu lists
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

The windowless `EaselInkTests` suite in `tests/NotesEditor` checks ink
resolution, chosen colours and token round trips; `EaselSelectionToolbarTests` checks which controls each
selection gets. Inert checks cover all font/fill/history behavior, the toolbar's text state helpers,
non-overlapping controls, actual selected/disabled states, light/dark drawing,
unchanged attributed text, scaled corner/edge admission, retained edge refusal after zoom, narrow toolbar
content height under legacy preferences and the compact native
URL editor. Shared Notes and capture editor checks exercise the reused classes.
