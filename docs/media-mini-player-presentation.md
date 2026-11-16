# Mini Player presentation

The Mini Player deck retains the original media page and episode for every
control. Rear cards never intercept or accept focus intended for the front card.

## Stack and card geometry

Collapsed cards are 33 points high. For depth `i`, opacity is
`max(0.4, 1 - i * 0.2)`, vertical offset is `-i * 7`, and width reduction is
`min(i * 10, 90)`. Rear cards are centered behind the front card. Expanded cards
are 66 points high, or 99 with the volume drawer, with 5-point spacing and an
8-point continuous corner radius.

A single player shows the 33-point transport row at rest, title/close/PiP chrome
on hover, and its volume drawer when expanded. Native Show All/Collapse controls,
a scrolling cap and narrow-sidebar fitting keep controls reachable. Failed
actions expose a 28-point message area. Motion is owned separately from these
target frames.

Option-clicking volume, or clicking while already muted, invokes the validated
native mute action. Otherwise the volume button toggles the drawer. The slider
cannot accept input, focus or accessibility traversal while collapsed.

## Titles

Overflowing visible titles can use the local
`ParcMiniPlayerMarqueeTitleEnabled` preference, which defaults off. The marquee
has 4/8-point masks, 32-point cycle spacing, a three-second initial delay and a
20-second cycle. Reduce Motion uses static truncation. The native title button
retains the complete title in its accessibility label and tooltip.

## Checks

`tests/MiniPlayerPresentation/check.py` compiles the production deck with stand-in
media types. It covers stack dimensions, expanded spacing, focus eligibility,
single-player layout, retained layers, marquee continuity, key-view rebuilding,
PiP actions that do not reveal the tab and hover-state isolation between players.
Whole-module compilation checks the real bridge. The same runner builds
`tests/MiniPlayerMotion`, which pins the cards' spring, moves the companion with
the deck, leaves views outside it alone and settles only the deck's own motion.
