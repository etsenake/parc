# Product backlog

This is an index of concrete unfinished work Parc intends to do, checked against
the implementation on November 10, 2026. Subsystem guides own the details and
the product decisions; [product status](parity.md) describes what exists. This
list does not authorize starting every task.

Completed fixes stay done. Missing test receipts, browser access, user confirmation
and routine release timing are not backlog work. Neither are parked, deferred or
declined ideas: the related guide keeps a sentence or two of reason, if there is
one, and a real report with a use case brings the item back. New
[performance](performance-navigation.md) work needs a concrete delay or resource
problem; a missing benchmark is not a defect.
Update or remove an item when its implementation lands; do not preserve completed
rows or percentage tables.

For otherwise unassigned work, retain the requested order: Routing, Windows,
Data, Folders, Archive, Command bar, Tab switcher, Peek and Onboarding.
Finish assigned work first.

## Folders

- Changing what data a Space uses refuses with no message when one of its Notes
  or Easels is also a Favorite, archived, or open in another Space on the old
  data. It needs the move explanation, shown before the sharing warning.
  [Folder moves](folder-moves.md#notes-and-easels-still-used-in-the-source-space),
  [Space management](space-management.md).

## Media

Casting continuity across navigation and picture in picture are implemented.
The remaining work is specific to these paths:

- FairPlay needs MSE pitch-policy forwarding.
  [FairPlay integration](../Engine/ParcNative/fairplay_chromium/README.md).

## Engine architecture

These shrink what each Chromium upgrade must refit, or what an engine build costs. None changes
what users see or hear today, and each must keep it that way.
[How Parc changes Chromium](chromium-seams.md) owns the details.

- Reverse playback's window planning and Safari's multi-track audio mixing still sit inside
  Chromium's renderers, so every upgrade must refit them there. Moving them into Parc files ships
  only with a real playback check that backward playback still shows frames and Safari-identity
  pages with two audio tracks still mix them.
- Optional experiments that could remove more patched media code, each needing its own measurement
  and approval because a regression would show as stalled or mis-composited protected video: a
  composite renderer and a separate FairPlay process with `CALayerHost`.

Keep details in the linked guide and current ownership only while a task is
active. Follow [the documentation policy](documentation.md); this index should
stay below 400 lines.
