# Air Traffic Control interaction

`LinkRoutingInteraction` owns editor focus restoration and native scrolling.
Return in a rule condition clears that rule's focused identity; it does not add
a condition or close the dialog. Inserting a new inline rule scrolls the last
rule to the top using a 0.3-second ease-in-out transition. Reduce Motion settles
that scroll immediately. Other mutations do not receive a generic editor fade.

The editor preserves focus and selection by rule and condition ID, restores
surviving controls with a safe fallback, and has explicit key-view order and
numbered accessibility labels. Destination refresh waits until editing and menu
tracking end because a selection snapshot cannot preserve marked input-method
composition. Validation/persistence errors are announced, with long errors
selectable in a nested Details sheet.

Routing does not generate a generic success toast for every link. Modifier-
explained link feedback belongs to [hovered-link status](web-interactions.md).
Source and component checks do not establish live keyboard or VoiceOver
acceptance; current browser-use restrictions still apply.
