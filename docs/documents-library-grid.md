# Easels & Notes Library cards

Library presents local Easels and Notes as two columns of cards. Each card is
140 × 140 points with 12-point corners and insets, 18-point appearance-aware
artwork and a wrapping 15-point semibold title. A note whose front matter sets an
emoji icon shows that emoji in place of the note artwork. When the title leaves
room, a note shows a short preview of its text under it, and every card ends with
when it was last edited ("Yesterday", "3 days ago"). Light appearance uses opaque
white cards with black titles; dark appearance uses raised gray cards and light
titles. Space tint stays behind the cards.

## What's listed

Notes are the Markdown and text files in the Space's Notes folder, chosen in
Settings → Edit Space → Notes folder (Documents/Parc Notes by default). Notes
saved anywhere else still open and edit normally; they just aren't listed. The
list follows the folder live, including Finder renames, deletes, moves and edits
from other apps, and it switches to a newly chosen folder straight away. Easels
are listed as before. Private windows show no documents.

Search matches titles, note text and "Easel". Every word has to match somewhere,
cards whose title matches come first, and each group stays newest first. An empty
search reads "Nothing matches that. Try fewer words?"; an empty Library reads
"Your local Easels and Notes will appear here."
[`DocumentsLibraryCatalog`](../Sources/ParcApp/DocumentsLibraryCatalog.swift)
holds this logic and has windowless tests.

## Actions

Click or Return opens a card in a tab. The ellipsis and context menu offer
Rename… plus, for notes, Show in Finder and Move to Trash…, while Easels keep
Delete…. Renaming a note renames its file, refuses a name that's already taken
with the reason, and moves the note's open tabs to the new file. Move to Trash
asks first, closes the note's tabs in every window, then moves the file to the
Trash. New Note is a header icon, leaving search nearly full-width. Escape,
including Escape from empty search, closes Library through its window owner.
Click and Return use profile/window-guarded callbacks with real document
identities.

Show in Library on a note's or an Easel's page menu opens this page with that
card selected, scrolled into view, focused and given a brief pop. A search that
would hide it is cleared, and a note saved outside the Notes folder is shown by
browsing its own folder. [`DocumentsLibraryReveal`](../Sources/ParcCore/DocumentsLibraryReveal.swift)
decides the folder, the match and whether the search clears, with windowless
tests.

## Grid

The native table virtualizes pairs of cards. When the window cannot fit both
140-point cards and their spacing, both cards shrink together, and the preview
gives up its lines before the title does. No document data or callback ownership
changes with layout. Other Library sections retain their own presentation and
lifecycle owners.
