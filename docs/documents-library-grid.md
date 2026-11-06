# Easels & Notes Library cards

with static `easel` or `note` artwork at 18 × 18, title, and document contents
as subtitle (empty for an Easel), with 12-point leading and trailing insets

is an opaque white 140 × 140 title-card grid on the Space-tinted panel: 18-point
coral easel artwork, wrapping 15-point semibold black title, hairline, and a
light drop shadow. Search is the full content width (“Search Easels…”). There
are no Open / Rename / Delete / New Easel footer bezels. Card title contrast is
independent of the Space tint — white tiles, black titles — which is why they
read as cards rather than themed buttons. A shutdown banner on that page is not
copied.

Dark Spaces use the catalog’s `easel-dark` / `note-dark` artwork (lighter ink
meant for a dark tile). Parc therefore paints an **opaque** raised gray tile
and a light title in dark appearance. A translucent white wash over the Space

Parc’s Easels & Notes page follows that tile: 12-point continuous corners,
12-point insets, 18-point appearance-resolved artwork, wrapping title only
(Note body stays searchable, not drawn on the card). Rename and Delete stay on
the card’s ellipsis / context menu. New Note is a header icon so search stays
nearly full-width; the combined “Easels & Notes” name and that create control
are documented adaptations. Escape / empty-search Escape closes Library through
the existing window close owner.

Parc uses the existing profile/window-guarded document callbacks for click and
Return, retaining its real local document identities and deletion confirmation.
The native table virtualizes two-card rows. At widths below the two 140-point
cards plus spacing, Parc reduces both card sides together to keep them visible;
this narrow-window rule is an adaptation. Remaining Archive / History / Media /
Downloads rail polish stays with Codex `codex/library-polish`.
