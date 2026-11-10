# Easel static appearance

The Easel shares the original document, text editor and embedded-page owners.
The canvas uses named white/black paper from the enclosing Space appearance, selection blue and content-specific
selection contours. Floating controls use the Easel semantic surface, outline,
ink and error colors. The text menu is a 50×88-point rail beside the selection,
with three 24-point plus/font/minus controls and a four-point gap from the
object. Its frame and native hit targets remain measured in screen points while
the canvas magnifies. Only corner resize marks are painted; all eligible edge
resize targets retain their native pointer and accessibility actions.

The Font control reveals the existing font, size and text-fill controls in a
200×85 panel. During native rich-text editing, that disclosure expands to
280×124 for the existing paragraph, emphasis and link controls. It stays within
the rail's native responder subtree, so no delayed action or detached inspector
can follow another document, selection or window. Selection replacement,
annotation hiding and owner retirement collapse it. The original text storage,
glyph layout, fill contour, typing history and document transactions remain the
only text owners. Palette callbacks reject a closed session.

The tool strip is a dark HUD pill: seven icon-only 32-point tools in
select / image / text / circle / square / arrow / scribble order, a filled
steel-blue selected cell, and light glyphs on a near-black continuous rounded
bar. It sits centered under the title. Link, webpage, undo and redo stay as
quiet 24-point paper chrome on the title row so those actions remain reachable
without joining the pill. The Share button (`square.and.arrow.up`) ends that
row; it opens the [Export as Image](easels.md#export-as-image) menu. The strip still follows the actual drawing mode and
scrolls horizontally when the window is narrower than the controls. Its explicit overlay scrollbar preserves the full control
height even under the system legacy-scrollbar preference. The ordinary Add Link action now presents the existing
window-owned URL editor, with a compact address-only layout. Its original
owner/visibility/IME/cancellation gates also cover this presentation. The rich
range-link editor retains its separate original-range/revision guard. Both use
plain controls, eight-point corners, semantic outlines and visible invalid-URL
feedback; no browser page is created by either editor itself.

## Native adaptations and boundaries

Parc's existing authored object colors are explicit RGB values and stay as
saved. Document paper, title ink and reusable floating controls resolve
white/black from the enclosing Space `contentOverBackgroundAppearance`, the
same Aqua/DarkAqua override Notes already inherit. Authored font geometry,
text fill, immutable capture pixels and the memory-only capture editor are unchanged.

The rail's disclosed family/size selectors and checkbox are native AppKit
controls; the expanded range inspector carries Parc's already-delivered rich
formatting actions. Inline disclosure replaces a second popup window to retain
the original native editing responder lifetime. `Aa` and SF Symbols substitute
for bundled image glyphs. Selected/pressed/disabled washes and native focus
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

Inert checks cover all font/fill/history behavior, native rail/disclosure bounds,
non-overlapping controls, actual selected/disabled states, light/dark drawing,
unchanged attributed text, scaled corner/edge admission, retained edge refusal after zoom, narrow toolbar
content height under legacy preferences and the compact native
URL editor. Shared Notes and capture editor checks exercise the reused classes.
These component checks establish source behavior. They do not establish live
browser interaction, VoiceOver/FKA acceptance or final visual polish.
