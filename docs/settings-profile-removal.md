# Profile removal presentation

Individual and unused-profile removal share `ProfileRemovalDialog` and
`ProfileRemovalButton`. The exact selected UUID/name, or the reviewed bulk
UUID/name set, remains authoritative throughout preparation, commit and recovery.
The sheet does not own the native deletion job.

## Parc integration and deliberate adaptations

The sheet is 450 points wide with content-derived height, 38-point horizontal
padding and 28-point footer padding. Its warning uses an 18-point title and
selectable 14-point text with four-point line spacing. Profile names and
`CONFIRM` are emphasized. The 13-point confirmation field has eight-point
padding and a one-point rounded border. Case-insensitive equality accepts the
confirmation without trimming it; Return and Delete read the same accepted state.

Cancel precedes Delete. Native buttons own press, keyboard and accessibility
behavior; disabled destructive styling takes priority over hover/press. Feedback,
long names and large bulk sets scroll within bounded sections rather than being
ellipsized. The warning identifies saved-tab/local-history deletion and retained
local files, captures and Easels.

Submit latches before dispatch and disables editing during preparation/commit.
Refusal preserves entered confirmation. Recovery uses the original journal and
Retry never reauthorizes a new target. Close cancels only reversible preparation;
after irreversible commit it leaves the native transaction intact. Success remains
visible with Done. Bulk results keep every reviewed member and actual status;
Retry skips completed members and cannot include newly created Profiles.

## Modal hover ownership integration

`SettingsHoverButton` supplies shared immediate hover with original application,
window, visibility and sheet lifetime checks. The removal button adds its palette
and keeps native NSButton press/action behavior. It does not maintain a parallel
tracking area, hover state or animation.

## Completed parent-focus integration

Confirmation initially owns focus. Disabling its editor moves focus to Cancel or
Close; retry returns to a surviving editable field or recovery action. Changed
feedback announces once, without stealing selection/focus on repeated refresh.
Done accepts Return; Escape retains marked-text refusal.

The common Settings focus owner captures pane, Profile and responder before
sheet entry. Completion restores only a surviving visible enabled original
control. If deletion changed the selected Profile, it returns to the surviving
Profile list. Settings closure invalidates pending focus restoration and cancels
only reversible work.

## Checks

Isolated model/native-boundary doubles cover atomic admission, protected Profiles,
preparation cancellation, journal recovery and partial completion without deleting
real profile storage. Inert sheet checks cover confirmation, duplicate/detached
requests, Unicode names, long feedback, legacy scrollbars, action labels,
Close/Done/Escape and bulk retries.
