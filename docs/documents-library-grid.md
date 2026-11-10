# Easels & Notes Library cards

Library presents local Easels and Notes as two columns of title cards. Each card
is 140 × 140 points with 12-point corners and insets, 18-point appearance-aware
artwork and a wrapping 15-point semibold title. Light appearance uses opaque
white cards with black titles; dark appearance uses raised gray cards and light
titles. Space tint stays behind the cards. Note bodies are searchable but are
not drawn on cards.

Rename and Delete live in the ellipsis/context menu. New Note is a header icon,
leaving search nearly full-width. Escape, including Escape from empty search,
closes Library through its window owner. Click and Return use profile/window-
guarded callbacks with real document identities and deletion confirmation.

The native table virtualizes pairs of cards. When the window cannot fit both
140-point cards and their spacing, both cards shrink together. No document data
or callback ownership changes with layout. Other Library sections retain their
own presentation and lifecycle owners.
