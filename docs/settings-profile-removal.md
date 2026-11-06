# Profile removal presentation — SET23

The individual and unused-profile removal sheets share `ProfileRemovalDialog`
and `ProfileRemovalButton`. The selected profile UUID/name and the bulk review's
fixed UUID/name set remain authoritative. No preparation, staging, commit,
recovery or final model-deletion implementation changes in this presentation work.

## Reference contract

retained contracts plus `components.py`, `arctypes.py` and `arcfn.py` resolve:

- `DeleteProfileDialog` fields: profile name, Delete/Cancel callbacks, confirmation
  string and accepted Boolean. `DeleteUnusedProfilesDialog` replaces the single
  name with the original array of names. Neither owns the native deletion job.
  and 28-point vertical footer padding. The warning starts below 38-point top
  warning with four-point line spacing; profile names and the literal `CONFIRM`
  are bold interpolations. The bulk names join with comma-space. The 13-point
  native input has eight-point padding and a one-point GrayA3 rounded stroke of
  radius five. Case-insensitive equality does not trim input; both Return and
  Delete read that accepted state. Cancel uses the cancel shortcut.
  vertical padding 10, height 36, continuous radius six, shadow radius two,
  one-point border. Pressed precedes hover; disabled destructive colors override
  both. Hover is a direct Boolean assignment, with no animation, scale or haptic.

The helpers answered these questions without new decompilation. Raw helper
outputs are retained under `work/settings-coordination/set23/`.

## Parc integration and deliberate adaptations

illustration and retains the warning hierarchy. The warning additionally names
Parc's saved-tab/local-history deletion and preserved files/captures/Easels.
Selectable text is bounded by scroll views for arbitrarily long profile names,
large review sets and actual native/save error messages; it is never ellipsized
or silently clipped. Height remains content-derived, with bounded scrolling
sections. The 13-point footer labels and eight-point inter-button gap retain Parc’s native
control adaptation; the reference label font/gap were not inferred from the
style body. AppKit rounded paths adapt SwiftUI continuous corners; real NSButton
owns press tracking, enabled state, keyboard activation and accessibility.

The process-owned native transaction requires progress and recoverable partial
outcomes beyond the reference's simple callback surface. The sheet latches each
submit before dispatch, disables editing during preparation/commit, and keeps
original confirmation text after refusal. Recovery uses the existing original
journal and presents Retry without reauthorizing a new target. Close remains
available after irreversible commit and delegates to the existing controller,
which cancels only still-reversible preparations. A successful native/model
outcome remains visible with Done. Bulk results retain every original name and
its actual status, including completed members; Retry excludes completed targets
and cannot add profiles created after review.

Confirmation initially owns focus. Disabling its field editor transfers focus
to Cancel/Close; a completed retry returns focus to the editable confirmation or
recovery action. Native titles supply current action accessibility names.
Changed feedback announces once; repeated store refresh does not repeat the
announcement or steal focus. Done owns Return, while the sheet window's native
cancel responder preserves Escape and the text editor's marked-text refusal.
SET26 owns the parent Settings pane/profile/responder capture and return after
`endSheet`; all existing sheet completion callbacks remain in that path.

## Checks

The production controller uses isolated native-boundary doubles in the model
and inert sheet checks. They neither start Chromium nor delete native profile
storage. The file-backed model suite covers atomic admission and protected
profiles; the controller suite covers preparation cancellation, original journal
recovery and partial completion. The new offscreen AppKit sheet suite covers
confirmation equality, detached/duplicate dispatch refusal, live action labels,
long feedback, Close/Done/default/Escape handling and bulk partial/retry results.
Light/dark captures exercise the actual production views, including recovery,
partial completion and completed cleanup. Whole-module typecheck and final SIL
are required before publication; these checks do not establish browser runtime,
VoiceOver operation or whole-product visual acceptance.

Finished-source receipts: `work/settings-coordination/set23/checks-2.log` records
37 model and 17 controller assertions. `sheet-checks-final-4.log` records 36
production-sheet assertions, including preservation of selected feedback text
through repeated store refresh, exact Unicode/name interpolation, and visible/hidden
legacy scrollbar viewport sizing. Independent review identified the legacy
viewport clipping; a failing inert check reproduced it before the correction.
`work/claude-split-checks/set23-final-4.json`
records the strict whole-module SIL pass in 57 seconds with zero diagnostics;
`set23-iteration-2.json` records the strict typecheck. The check executable is
Xcode's `swiftc` (Apple Swift 6.4, swiftlang-6.4.0.34.1); source hashes and six
light/dark captures are retained in `work/settings-coordination/set23/`.

Independent reviewer `set23_removal/set23_review` cleared the exact finished
source after the legacy-scroller correction. The retained hash manifest is
`source-hashes-final.json` (SHA256
`5d9de5cb845ce447c0a3f7a4a2060ce39d5231932e5b1993aa48bbf2ac2417b3`).
SET26's common parent focus publication is now integrated through the unchanged
native sheet callback path; the original SET23 assignment is complete.

### Modal hover ownership integration

SET25's published `SettingsHoverButton` owns immediate hover for both deletion
sheet buttons. The sheet button retains its recovered palette and NSButton's
native pressed/action behavior; it no longer keeps a second tracking-area or
hover Boolean. Original key-window/application ownership, visibility,
hide/close/detach, sheet interruption, replacement tracking areas and old-window
events use the same checked owner as the pane controls. This follow-through
resolves SET25's modal interruption dependency without adding animation or
haptics. The unchanged common base already has 28 inert lifetime assertions;
this integration rechecks the actual sheet cohort and final whole-module SIL.

The integrated sheet cohort passes all 36 assertions
(`work/settings-coordination/set23/sheet-checks-hover.log`) and finished
whole-module SIL passes in 37 seconds with zero diagnostics
(`work/claude-split-checks/set23-hover-final.json`). Fresh reviewer
`set23_removal/set23_hover_review` cleared the exact two source/script hashes
in `hover-source-hashes.json`; the previous completed reviewer was retired.

### Completed parent-focus integration

SET26 publication `b036bb9bb4803b1fa34a73688b00e3298aa185a4` is reconciled.
Both removal callback groups are byte-identical to their reviewed publication.
The common owner captures the original Settings pane/Profile/responder before
sheet entry and restores only a surviving, visible and enabled original control
after completion. If removal changed the selected Profile, it explicitly returns
to the surviving Profile list rather than another Profile's old bookmark.
Closing Settings invalidates the pending restoration and cancels only reversible
preparations through the unchanged removal controller. The dependency's 21 inert
native assertions, independently cleared source and final 48-second SIL receipt
were inspected; no duplicate or functional browser checks were introduced.
SET23 is complete with both required common hover and parent-focus integrations.
