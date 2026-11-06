# App icon picker interaction

ICON10 owns the Settings icon rows in `IconSettingsView.swift`. It preserves
`AppIconController` as the sole owner of selection, atomic persistence, native
identity application, and Finder retry. ICON11 supplies validated image loading
through the unchanged `Variant.image` interface; ICON09 owns the native image
representations. The picker scales those images proportionally in the recovered
64-point frame and does not crop, recolor, or create a competing preview export.

## Reference contract

`4e452201e483b5480c0403a9ef8566e10515cdcb78828622ff9032b202e29547`.
The recovered-components index, Swift type table, cross-reference index and
annotated-function helper resolved this row without new decompilation. Existing
its onboarding-specific preferred-option and hover settings are not copied into
the icon pane.

- `AppIconOptionView` stores its settings store and `AppIconAndUIState`, with
  completed `onTapGesture` encloses the row. The radio binding's setter at
  fifth byte `1`, and the type-table field order establish `showBorder=false`,
  `scaleOnHover=false`, `roundedCorners=true`, `hideContent=true`, and
  `skipPaddingBeforeCheckbox=true`. Its internal radio height is 67; the
- `RadioGroupButton` uses a plain SwiftUI button at
  preferred-heart spring and delayed reset are also inapplicable to this pane.
  superseded by this recovered frame and
  and state line; current selection shows uppercased `Current Icon` in accent
  credit on the independently authored Parc image.

These helpers establish the control composition and options. They do not recover
the platform implementation of SwiftUI's plain-button pressed palette. Parc's
native pressed indicator uses its existing white-to-gray change, while the
row and image remain at their resting scale. The 81-point outer row spacing and
group border retain the earlier permitted appearance measurements. The current
marker now sits after the title without shifting that title when selection
changes. There are no picker hover springs, delayed selection timers, or
speculative row animations to cancel under Reduce Motion.

## Native control adaptation

Each row is one native button with a radio accessibility role, named once by its
variant, in a named radio group. Decorative artwork and labels are excluded from
the accessible child list. The current value comes only from the controller;
native button state never optimistically toggles before the atomic save.

The full row participates in hit testing. Mouse-down arms the control and shows
its pressed indicator; dragging out disarms that appearance, dragging back
re-arms it, and release inside performs one action. Both bounds and visibleRect
must contain the pointer: an unclipped AppKit view's visibleRect can exceed its
bounds. Space/Return/keypad Enter arm on key-down and commit on matching key-up;
held repeat and stray releases do not save again. Escape cancels. Unmodified
arrows focus, reveal and select the adjacent row, stopping at the ends. The
selected row is the group's native Tab entry; any row may receive arrow or mouse
focus. The focus ring is confined to the radio indicator and requires the
original window to be key, the app to be active and the row to be first responder.
Key/application loss and return explicitly redraw that retained responder.

Focus loss, pane hiding, detachment, disabling, window key loss/close, app
deactivation and an externally changed selection cancel unfinished input.
Observers belong to the attached window and are removed on detachment/deinit.
A retained closed Settings window refuses stale AX or programmatic activation
until it becomes key again. Pane subscriptions and row callbacks weakly capture
their owners. No global event monitor, browser bridge, callback timer, or extra
system-identity writer is introduced.

Selection and accessibility activation synchronously reread the controller after
its action. A failed write leaves the old radio value and current badge intact;
status text and Finder retry continue through the existing owner. This is a
native adaptation for truthful persistence and cancellation, not a claim that

## Checks

`bash scripts/test-icon-settings.sh` compiles the actual picker and controller
into an inert AppKit runner. It uses a disposable preference directory and an
injected identity recorder; it does not open a browser, post system events, or
change the running app/Dock/Finder identity. It checks real control hit targets,
pressed/release/cancel handling, bounds, keyboard focus and repeat, single AX
role/value/action, selection synchronization, save failure, view lifetime,
window interruption and attachment. An optional output directory writes native
light/dark component renders for inspection. These are component evidence,
not live VoiceOver/FKA or integrated browser acceptance.

Final check receipts and helper evidence are local under
`work/app-icon-checks/icon10`; whole-module compiler receipts are
`work/claude-split-checks/icon10-picker-review-fix.{json,log}`. All 45 component
assertions pass; the finished whole-module SIL check has zero diagnostics.
Native light/dark renders were inspected for layout and state readout. Fresh
independent reviewer `icon10_picker/icon10_review` cleared the exact finished
source after the inactive-window focus-ring correction. Whole-product visual
polish remains separately tracked.
