# Mini Player presentation (MEDIA13)

opacity, y offset and width offset per original media item. Its view-state
`max(0.4, 1 - index * 0.2)` opacity, `-index * 7` y offset and
expansion, full opacity and 5-point inter-card spacing. The view body at
composition uses 33-point bands and horizontal padding. These are disassembly

Parc keeps those metrics for the stack and expanded cards, and centers each
narrower rear card behind the leading original episode. A single player uses
the same hover chrome as a stacked front card: 33-point transport (favicon,
previous, play, next, volume) while idle, 66-point title/close/PiP chrome on
hover, and 99 points with the in-card volume slider. A native Show All/Collapse header,
scrolling cap, fitting control widths on narrow sidebars, 28-point unavailable
message, system glyphs and fonts, and native slider are explicit AppKit
adaptations. Rear cards do not accept focus or intercept the front card; the
existing actions retain their original page and episode leases. The motion owner
session; Parc uses the existing validated native mute action for those cases and
otherwise toggles the volume drawer. The reference checks the current event's
modifier flags, and the muted keypath is the state field set by reducer

`miniPlayerMarqueeTitleEnabled` and the feature flag has the same name in
wraps the offset and draws a second copy when the title overflows. The call
spacing, a 3-second delay and speed 1; the drawing formula divides elapsed time
by 20 before applying that speed, giving a 20-second cycle. Parc uses those
restart requirement; remote overrides can change the effective value. Parc
defaults the marquee off and uses the local `ParcMiniPlayerMarqueeTitleEnabled`
preference instead of the excluded remote service. Static truncation under
reduced motion is an explicit accessibility adaptation. The transparent
native title button remains the action and accessibility owner, with its full
title available as its accessibility label and tooltip. These choices do not

The off-screen `tests/MiniPlayerPresentation/check.py` compiles the production
deck with stand-in media types and checks stack dimensions, expanded spacing,
front-card focus eligibility, the single-player layout, retained backing layers,
marquee continuity under identical palette updates, the installed key-view
chain after expansion, that Open Picture in Picture does not reveal the tab,
and that a later player after hover-off does not inherit expansion. Whole-module compilation uses the real bridge.
No functional browser test or playback experiment was run.
