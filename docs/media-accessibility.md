# Media presentation and accessibility investigation

MEDIA16 is source-complete under the current check policy. PiP is outside this
[Mini Player](media-mini-player.md#reference-and-adaptations) and
[Casting](media-casting.md#reference-and-native-ownership). The current pinned
Chromium source is 156.0.8078.48.

## Cast

The retained Cast contract identifies the original page's shared router
controller and native dialog coordinator, not a Parc-specific device list.
Chromium's [142 Cast view](https://raw.githubusercontent.com/chromium/chromium/142.0.7444.176/chrome/browser/ui/views/media_router/cast_dialog_view.cc)
and the pinned 156 view both construct a close button and Sources control,
use a preferred-width bubble and the real sink views, and restore focus to the
updated selected sink for its accessibility label. The current native adapter
continues to use the genuine 156 controller/view and exact page parent. This
source comparison is evidence of the upstream implementations, not proof of
not establish pixel measurements.

## Site permission and screen sharing

its specific layout, symbol, decisions and current-engine follow-up adaptations
are documented in [Web interactions](web-interactions.md#dialogs-authentication-certificates-and-permissions--web15).
screen-sharing path and Chromium's desktop-picker views. For ordinary
screen/window/tab source lists Parc forwards the genuine lists to the pinned
Chromium desktop picker, including delegated macOS system selection. A
current-tab-only request uses Chromium's dedicated 600-point dialog: its title
receives initial focus, Allow is delayed and Return is not a default grant.
The callback checks the exact original primary frame again before delivery.
The delegated source path uses an exact-ID lease shared with the native creation callback: worker teardown
closes any session not explicitly transferred by a genuine selection. The
creation callback retains the lease independently of the worker, so a late ID
is closed even after that worker stops. An accepted result is revalidated by the
original request owner; abandonment or stale delivery closes its transferred
native session.
Chromium's [142 picker](https://raw.githubusercontent.com/chromium/chromium/142.0.7444.176/chrome/browser/ui/views/desktop_capture/desktop_media_picker_views.cc)
focuses the selected source category and uses its own source controls; this
adapter retains the original request/document, profile, page, window and security
reservation; it revokes immediately and defers teardown outside Chromium's
controller stack. A retained session carries an un-abandoned result across the
actual view-destroy notification, checks the owner and competing reservations
again at delivery, and discards an abandoned or stale result. The upstream
picker manager receives a balanced close when the host cancels before a result.
Native and upstream picker units pass pinned compilation, an inert lease
check covers ordering and 500 creation/release races, and 564 cumulative overlay
targets replay in both directions. The exact current-tab increment was
independently reviewed. Functional browser and system-picker interactions were
not run. Overlay 253 is pending the dedicated engine owner.

## Mini Player

The recovered `MediaControlsHostingView` owns the SwiftUI deck but has no
responder override; the individual `MiniPlayerView` keyboard stops have not
been recovered. See [sidebar accessibility](sidebar-accessibility.md) for the
negative findings. Parc's explicit row and button stops are an accessibility
deck relinks the sidebar's key-view chain when its rows, capabilities, or
expansion change. Playback, microphone, camera and mute controls update both
the current action; their exposed button cells and images receive the same
names. The expand control names its current action and count. A retiring focused
row or disappearing expand control yields focus outside the deck only in its
active key window. A failed action expands a collapsed card to expose its
message before announcing it. These native accessibility adaptations retain the
original control callbacks and episode validation. An off-screen inert
component check covers the dynamic names, expanded state and error visibility.
The volume drawer keeps its fade while excluding a collapsed slider from hit
testing, focus and accessibility; focus returns to a visible control on collapse
or capability loss. The integrated host lease remains tied to the original
window. MEDIA14's presentation check and MEDIA12's independent review cover
those integrations; the accessibility component check passes on the combined
source. No Full Keyboard Access, VoiceOver, functional browser or device test is
claimed from this investigation.
