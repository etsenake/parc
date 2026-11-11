# Dialogs

Every alert, confirmation and name prompt a person sees in Parc's own windows is
18-point title, 14-point message, 36-point buttons with Escape and return hints,
and a red Delete for destructive confirmations. Web page alerts and the extension
remove sheet are drawn by the engine in the same style. The system alert is not
used for anything Parc owns. The one exception is the "Parc couldn’t start"
error, which can appear before any Parc window or engine exists.

## Attachment and results

A dialog is a sheet on a window (`begin(for:)`) or, where it never had a window
to hang from, app-modal (`runModal()`). A window that already shows a sheet
refuses an unqueued dialog; a caller that always showed its alert passes
error alert that replaces `presentError`.

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
own Return and Escape. `scripts/test-arc-dialog.sh` covers these cases.
