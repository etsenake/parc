# Dialogs

Every alert, confirmation and name prompt a person sees in Parc's own windows is
a `ParcDialog` (`Sources/ParcKit/ParcDialog.swift`): the popover background, an
18-point title, 14-point message, 36-point buttons with Escape and return hints,
and a red Delete for destructive confirmations. The engine draws its own sheets in
the same style with the same checkbox and field card
(`Engine/ParcNative/dialog_style.mm`): web page and DevTools-window alerts,
extension install and remove, password/address/card saving, website sign-in,
open-in-app, unresponsive pages, the notifications-permission nudge and the
download, caret-browsing and private-window decisions. The system alert is not
used for anything Parc owns. The exceptions are the "Parc couldn’t start" error
and the [saved-sidebar rescue](windows-lifecycle.md#saved-sidebar-backups-and-startup-rescue),
which appear before any Parc window or engine exists.

## Attachment and results

A dialog is a sheet on a window (`begin(for:)`) or, where it never had a window
to hang from, app-modal (`runModal()`). A window that already shows a sheet
refuses an unqueued dialog; a caller that always showed its alert passes
`queued`. `ParcDialog.inform` shows a title and message with OK, `Content(error:)`
builds what `NSAlert(error:)` showed, and `ParcDialog.present` is the app-modal
error alert that replaces `presentError`.

Chromium's own Views dialogs that belong to a page or window, such as DevTools'
"Allow DevTools to edit files" prompt, the remote-debugging approval, the
process-sharing restart and the File System Access warnings, attach as a child
window (`Engine/ParcNative/constrained_dialog.mm`). A page's dialog sits centred
along the top of the tab, docked DevTools pane, extension pop-up or side panel
that asked, follows it as the window moves or resizes, hides with its tab, keeps
the page or DevTools pane blocked until it closes, closes with its page or window
and hands focus back to it. A window's dialog sits along the top of the page area.
Each holds the window's security reservation and waits while another prompt has it.

Device pickers for Web Bluetooth (the device chooser and the scanning prompt),
WebUSB, WebHID and Web Serial never reach Chromium's Views chooser bubble, which
needs a Views browser window to anchor to. Parc's content browser client returns
Chrome's Bluetooth, USB, HID and Serial delegates with only their chooser step
replaced (`Engine/ParcNative/native_device_delegates.cc`): each builds the same
chooser controller Chrome builds and shows it with Parc's native device chooser
(`Engine/ParcNative/device_chooser.mm`), attached to the requesting page's window.
Permissions, policy, blocklists and device lists stay Chrome's. Closing the
request, the page or the frame closes the picker; when no picker can be shown the
request is refused as if the person cancelled. Extension pages and HID requests
from a `<webview>` guest (after its embedder allows them) use the same picker.

The response says which button ended it: confirm, the checkbox-ticked confirm,
secondary (the second action, left of confirm), auxiliary (leftmost, for example
Keep Open) or cancel. Buttons keep the order a system alert had. A choice between
actions with no Cancel button (Retry, Close Page, Keep Open) ignores Escape;
a dialog with Cancel or only OK closes on it.

## Fields and checkbox

A text field sits on a soft rounded card with the same tint as the Space name
card, 16 points under the message and 36 points tall, with 12-point padding. Like
Parc's other name inputs it has no focus ring and shows focus by its caret; a
press on the card's padding still focuses it. A required field disables the
confirm button while its trimmed text is empty. Long error text uses `details`,
a selectable read-only card that scrolls.

The "don’t ask again" style checkbox is `ParcSelectionCheckbox`, the circle and
filled check-circle the onboarding bookmark picker draws (`ParcSelectionMark`),
tinted with the onboarding action blue and read as Selected or Not selected. It
is an `NSButton` switch, so VoiceOver reads a checkbox and the system draws
keyboard focus; Space toggles it and every other key passes on.

## Keys

Return confirms and Escape cancels wherever focus is, including the field and the
checkbox, and keypad Enter confirms. An input method that is composing keeps its
own Return and Escape. `ParcDialogTests` covers dialog decisions, required fields and marked text.
