# Settings pane presentation

SET24 preserves the native preference toolbar and the existing pane, profile,
preference and command owners. The shared AppKit presentation now follows the
control-background card. The completed Icon radio control and Shortcuts surfaces
retain their established layout, palette, selection and native input paths.

## Retained contract

`4e452201e483b5480c0403a9ef8566e10515cdcb78828622ff9032b202e29547`.
The local recovered-components index, Swift type/witness table, cross-reference
index and annotated functions resolved this work without new decompilation.

- `PreferencesPaneSectionBackground` has cornerRadius, padding and backgroundColor
  rectangle, native separatorColor stroke width two, then clips with the same
  shape. The visible stroke is one point inside the section. Links producer
  opacity and six-point radius. Unrelated modal-specific colors remain with
  their owners.
  Privacy and Security/lock.fill/blue, Passwords/key.fill/green, Credit Cards/
  creditcard.and.123/yellow, Notifications/bell.fill/orange and Clear Browsing
  and accent arrow.right, with five-point all-side padding (34-point row).
  Disabled text uses disabledControlTextColor and whole-content opacity is 0.25. Its separate hover owner is documented in
  [Settings motion](settings-motion.md).
  speaker.wave.2.fill and hand.tap.fill blue glyphs; green
  rectangle.topthird.inset.filled; red ellipsis.rectangle and quote.opening;
  and purple paintpalette.fill. Parc uses those real system symbols in passive
  continuous-radius badges beside the original native controls. Excluded Boosts
  is not restored. The user-accepted PiP state is not reopened.
- The retained preference shell/toolbar contract in [Settings](settings.md)
  remains authoritative. Included toolbar order is General, Profiles, Links,
  Symbols at one size: `person.crop.square.filled.and.at.rectangle` for the card,
  `gearshape`, `person`, `macwindow.on.rectangle` for Links, `keyboard` and
  `slider.horizontal.3` (both long names are strings in its executable). Its
  PrefsGeneral/LinksPrefPaneIcon catalog images are not the toolbar glyphs; as
  24-point bitmaps they drew larger and heavier than the symbols beside them.
  SET27 separately owns the requested personal-name membership pane before these
  ordinary preference tabs. Native NSToolbar selection tint remains the owner; Icon keeps approved Parc
  branding. AppKit supplies all remaining ordinary system glyphs.

## Native integration and adaptations

SettingsGroupView uses a native layer with continuous corner geometry and a
one-point inside border to represent the original clipped SwiftUI stroke.
The enabled native label color is an explicit AppKit representation of the
original light black/dark white branch. Dynamic native colors resolve inside
the actual view appearance, including after
an appearance change. It does not cache a light or dark color globally. Ordinary
native controls retain their enabled state, focus ring, target/action and value;
Advanced full-URL uses the recovered trailing switch while keeping its existing
preference selector. Profile search suggestions uses the same trailing switch
structure without changing the native preference operation.

SettingsCommandButton is one native button with a passive badge, label and arrow.
It supplies one accessible name/role and does not expose decorative descendants.
Its native action still reaches SET21's exact selected-profile dispatcher. The
native profile table remains the authoritative selected Profile; the name and
Space count retain separate, nonoverlapping text frames and native truncation.
Neither decoration nor a new shadow selection state can change that Profile.

The 684×562 shell, 64-point margins, 206/336-point Profile columns,
retained scroll offsets and local restore/replay/Space-assignment controls remain
explicit AppKit/account-free adaptations. General keeps the included Warn, Previews and Profile management order before
1.171's capture: three sections of switch rows (sound/haptics; restore, window
dragging, full URL, Shared Quotes; theme data) with 40-point rows, 50 with a note,
1-point dividers inset 10, sections 10 apart; Parc's sidebar width is a fourth
section; More Settings… leads and Export Data trails a 24-point button row in
of this pane. Profile search retains
the engine, Manage Search and trailing suggestions row order; a separate help
line preserves truthful loading/failure feedback. The data heading sits outside
its compact group. Native failure/help rows stay visible
when their real owners report problems. The included control inventory and these
adaptations account for differences from screenshots containing excluded cloud,
AI, updater, live-integration and Boosts rows. This delivery does not substitute
new placeholders for excluded controls or remeasure completed Icon/Shortcuts work.

## Checks and evidence

Actual production components are checked by `tests/SettingsPresentation/check.py`;
the emitted light/dark native images are inspected alongside retained reference
General, Profiles and Advanced captures. Input ownership, descendant isolation,
truncation containment, disabled palette and native toolbar representations are
covered without changing personal preferences or creating a browser. Finished
source passed the full app whole-module SIL check in 31 seconds with zero
compiler diagnostics. The focused native presentation check passed 48 assertions;
the actual Download Location component passed 33 after its extraction helper
was updated for the shared group source and current card position. No author
check was replaced by a source-string claim. Focus/interruption and
motion retain SET26/SET25's independent requirements and evidence.

The extra whole-pane layout captures slice the actual pane builders, apply the
production small-switch sizes/help fonts and supply neutral inert data; they are not complete Settings-controller sessions. Native
source-list selection drawing in these offscreen captures does not establish
active-window selection appearance. Original native selection ownership remains
unchanged. Links deliberately centers its second switch beside the combined
label/note row; the note ends before the switch horizontally. Its configured
light/dark capture preserves that two-line geometry without an unnecessary edit.

Local annotated-function and render receipts live in
`work/settings-set24-evidence`. These component/compile checks do not claim
functional browser testing, live VoiceOver/FKA acceptance or final whole-product
polish.
