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

## Link destinations

The rule editor offers Most Recent Space and each Space by name, never Profile names. External links use the first matching rule. A missing explicit Space falls back
to the frontmost eligible window and its active Space; without one, Parc creates
a window using the most recent surviving Space. Other unavailable destinations
fall back through the rule store's recent-Space policy.

Internal current-tab, foreground-tab and background-tab links retain the
original navigation request and disposition. An unavailable rule destination
leaves the original navigation in place. A background route keeps an existing
destination's selection and visibility; a newly created destination appears
without taking focus. Once an admitted route starts, failed destination creation
reports failure rather than reconstructing the navigation from a URL.

Private windows from every source, including the page menu's Open Link in
Incognito Window and extensions, share one private session per profile whose
lifetime covers each creation; see
[private navigation lifecycle](private-route-lifecycle.md).
