# Parc dialog style

`Engine/ParcNative/dialog_style.{h,mm}` draws the engine's own sheets in Parc's
dialog look: the extension install and remove sheets, page and auxiliary-page
JavaScript dialogs, password/address/card save prompts, website sign-in,
open-in-app, the unresponsive-page and notifications-permission sheets and the
browser decision sheets. The app's `ParcDialog.swift` draws the same dialog;
keep their metrics together.

The module supplies the background, Parc's mark, title and message layout,
key-badged buttons (primary, red destructive, Escape and unbadged auxiliary),
Parc's circular selection checkbox and tinted rounded input card (both matching
the app's [dialogs](../../docs/dialogs.md)), a footer that wraps crowded buttons onto rows above, `PCDialogPanel`
(keypad Enter, Escape and input-method composition) and `PCDialogPrompt`, an
NSAlert-shaped decision sheet.

## Executable AppKit checks

```sh
swift test --filter DialogStyleTests
```

The suite opens
offscreen test windows. Its 34 assertions cover page-window sheet attachment,
responses from clicks, Return, keypad Enter and Escape, a chosen Escape button,
another owner ending the sheet, prompt lifetime without an owner, footer
wrapping and capped over-long buttons, composition keeping Return and Escape,
secure fields, the field card's size, padding and press-to-focus, and the
checkbox's role, Selected/Not selected value, Space toggle (not modified or
held Space) and Return pass-through. Each presenter's own suite covers its
behaviour.
