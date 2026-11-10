# Media interactions — tab audio

The sidebar context menu and audible/muted indicator use the original live
Chromium page, independently of the Mini Player episode. The indicator appears
when the page is audible or muted. Favorite and split-child menus use the same
action; a compact split child retains context and accessibility controls even
when its indicator does not fit.

## Original-page actions

Menu and pointer actions capture an immutable document, WebContents, Profile,
Browser and mute-state lease. Replacement, transfer, retirement, mute revision
changes (including mute/unmute cycles) or loss of the original window refuse the
action. Guarded selectors keep unsupported older engines unavailable.
`DidUpdateAudioMutingState` and `OnAudioStateChanged` publish coalesced updates
from Chromium rather than a saved tab flag.

The 14-point speaker uses three animated wave paths and a diagonal clip for mute.
Its per-tab host survives sidebar row reconstruction; theme ink and Reduce
Motion follow the existing view owner. The Mini Player volume control mutes
when Option is held or the tab is already muted; otherwise it toggles its drawer.

## Global mute

Mute All Tabs and Unmute All Tabs run from the original Command Bar owner over a
snapshot of live native page frames across windows and Profiles. Each target
rechecks its original WebContents, document, Browser and Profile before mutation;
new or transferred pages cannot replace a captured target. The submitting
window/revision must remain current, registered, active, key and free of sheets
or security reservations. A crashed page may retain the mute setting for reload.

## Validation

Swift/native compiler checks and inert speaker components cover the API boundary,
lease guards and host reparenting animation.
