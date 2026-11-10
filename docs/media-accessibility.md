# Media presentation and accessibility

Media controls preserve the actual page, document, Profile and window that owns
each operation. Casting, website permission prompts and the Mini Player use
separate presentation owners. PiP's accepted implementation is not reopened by
this document.

## Cast

The native adapter uses Chromium's genuine media-router controller and dialog
view for the original page. Device lists, Sources, selected-sink accessibility
labels and focus remain upstream-owned. Parc does not maintain a parallel
synthetic device list. See [casting](media-casting.md).

## Site permission and screen sharing

Camera/microphone requests use the native site-permission presentation; macOS
owns the system permission. Ordinary screen/window/tab sharing forwards genuine
source lists to Chromium's picker, including delegated macOS selection.
Current-tab-only sharing uses its dedicated 600-point dialog: the title receives
initial focus, Allow is delayed and Return does not grant permission by default.

The callback rechecks the exact primary frame before delivery. A delegated
session uses an exact-ID lease shared with creation: worker teardown closes any
session not explicitly transferred by a genuine selection, and a late creation
ID is closed even after the worker stops. Stale or abandoned delivery closes a
transferred session rather than leaking it.

The presentation retains original document, Profile, page, window and security
reservation. Revocation is immediate; teardown is deferred beyond Chromium's
controller stack. Results surviving a view-destroy callback are revalidated
against original ownership and competing reservations before delivery. A
cancelled host balances the upstream picker manager's close notification.

## Mini Player

The deck rebuilds its key-view chain when rows, capabilities or expansion
change. Playback, microphone, camera and mute buttons update their accessibility
names, images and tooltips to the current action. Expand announces its action
and player count. A retiring focused row yields focus outside the deck only in
its active key window.

Failed actions expand a collapsed card before exposing and announcing the
message. The volume drawer retains its fade but removes its collapsed slider
from hit testing, focus and accessibility; collapse or capability loss returns
focus to a visible control. All callbacks retain their exact episode lease.
See [presentation](media-mini-player-presentation.md).

## Validation

Native compilation and inert lease checks cover stale result ordering and
creation/release races. Component checks cover dynamic labels, expanded state,
error visibility, drawer focus and exact window ownership. They do not establish
live system-picker interaction, device behavior, Full Keyboard Access or
VoiceOver acceptance.
