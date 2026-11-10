# Settings pane presentation

Settings uses the native preference toolbar and existing pane, Profile,
preference and command owners. The ordinary tabs are General, Profiles, Links,
Shortcuts, Icon and Advanced, after the personal membership pane. Icon keeps
approved Parc artwork; native toolbar selection tint remains authoritative.

## Native integration and adaptations

`SettingsGroupView` uses continuous six-point corners, ten-point padding, native
quinary-label background at 0.3 opacity and a one-point inside separator border.
Dynamic colors resolve in the actual view appearance, including after changes;
they are not cached globally. Native controls retain enabled state, focus ring,
target/action and value. Advanced full-URL and Profile search suggestions use
trailing switches with their existing preference operations.

`SettingsCommandButton` is one native accessible button with passive badge,
label and arrow. The 24-point symbol badge plus five-point padding makes a
34-point row. Disabled content uses disabled-control text and quarter opacity.
Profile actions preserve the original selected Profile dispatcher; decorative
children do not become accessibility targets or a second selection model.
The name and Space count use separate nonoverlapping truncation frames.

The shell uses 684×562 points with 64-point margins and 206/336-point Profile
columns. Scroll offsets and local restore, Replay onboarding and Space-assignment
controls remain supported. General retains Warn, Previews and Profile management,
then local onboarding/default-browser additions. Replay onboarding must remain
available even when changing visual layout.

Advanced groups sound/haptics; restore/window dragging/full URL/Shared Quotes;
and theme data, followed by Parc's sidebar width. Rows are 40 points high or 50
with a note; dividers inset ten points and sections are ten points apart.
More Settings and Export Data share a 24-point button row. Excluded Boosts are
not restored. Included controls are never removed to match an old screenshot.

Profile search preserves engine, Manage Search and suggestions order. Real
loading/failure feedback uses a separate help line; data headings sit outside
their compact groups. Links keeps its second switch centered beside the combined
label/note while preventing horizontal overlap.

## Checks and evidence

`tests/SettingsPresentation/check.py` covers production component layout,
input ownership, decorative-descendant isolation, truncation, disabled colors
and toolbar representations. Shared Download Location checks cover that component's
integration. Typechecking/SIL complement these inert checks.

Offscreen components do not establish active-window selection appearance,
complete controller behavior, VoiceOver/FKA acceptance or final product polish.
Focus and motion have separate [Settings](settings.md) and
[motion](settings-motion.md) contracts.
