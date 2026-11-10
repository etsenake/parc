# Recent-tab switcher

The recent-tab switcher follows each window's actual most-recent selections.
A split is one item, represented by its focused pane. Dates seed unvisited items
but preview focus does not select a tab, change MRU order or refresh auto-archive
activity.

## Session and ownership

Next/Previous keyboard commands enter a held-modifier session. A native priority
monitor exists only while that session is active. Presentation waits 100 ms:
quick release selects immediately without flashing a panel, including when the
native command acknowledgement arrives after release.

The panel is a nonactivating child of the original browser window, whose first
responder stays intact. Selection is committed only to a still-valid original
window, Space, item and page. Space changes, app deactivation, parent key/window
changes, selection changes, security reservations or changed command bindings
invalidate the session.

At most five cards are visible. A sixth reserve item can replace a closed card
but is excluded from cycling, input, accessibility and thumbnail requests until
promoted. Preview focus itself never creates or loads a native page.

## Closing and cancellation

W requests the focused item's real close path. The panel hides while native
consent is pending. Confirmed close removes the item and promotes the reserve,
keeping the focused position when possible and clamping it otherwise. Refused
close returns to the same cards only if the session is still valid.

Releasing the held modifier during pending close ends the session without
selecting an item being retired. Further key repeats cannot issue another close
while consent is outstanding. A sheet or security change cancels rather than
retargeting the action.

<a id="original-card-surface-and-ownership--kb21"></a>

## Cards and thumbnails

Thumbnail work uses Chromium's `ThumbnailTabHelper` for the exact live native
page and Profile. Only visible cards and the focused preview request images.
Work deferred out of native callbacks revalidates its generation and owner;
a missing page never triggers URL-based creation.

The card strip is 190 points high with 16-point outer padding. Cards are about
182 points wide with 12-point content padding, 14-point medium titles and rounded
preview corners. Focus has one rounded highlight; pointer focus and keyboard
focus share it. The panel uses popover material, follows the parent's active
appearance and stays inside the screen with a 40-point margin.

Focused-card scrolling uses a 0.1-second ease-out. Reordering and reserve
promotion use a 0.15-second spring with damping 0.95. Reduce Motion skips those
transitions. Panel placement and opening/closing are direct rather than adding
another alpha animation.

Card content reflects the actual item:

- A named split uses its own title/icon and a pane-count badge. An unnamed split
  uses the child favicons. Multiple previews preserve pane orientation.
- Notes and Easels use native document templates and two-line titles.
- A missing screenshot uses a neutral placeholder; private content keeps its
  private fallback instead of borrowing another Profile's image.
- Recording state adds a marker. A Peek snapshot is inset over the dimmed parent.

Cards do not add another navigation surface or mutate the represented item.

## Held-key input

The session recognizes the configured Next/Previous commands, their alternate
forms and Left/Right. The primary modifier set is matched exactly; Shift can
reverse direction, while Caps Lock and function-state bits are ignored.
Modifier changes are consumed and commit when the held primary modifier is
released, including when other modifiers remain down.

Escape cancels. W follows the close policy above. Unknown keys are consumed
without dismissing or forwarding them to a page behind the panel. Repeated
cycling is supported while no close is pending. Physical-key handling preserves
the configured backtick shortcut independently of typed text.

## Sources and validation

The shell switcher controller, recent-item model and native keyboard priority
monitor own the session. `RecentTabSwitcherTests` and the keyboard/component
checks cover ordering, bounded reserves, stale sessions, close refusal,
modifier release and delayed presentation.
