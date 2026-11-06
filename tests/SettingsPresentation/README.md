# Native Settings presentation check

Run `python3 tests/SettingsPresentation/check.py /absolute/output-directory`
with full Xcode selected. It compiles the actual production group, badge,
command-button, profile-cell and toolbar resource loader with the existing
native LayoutView. No browser is created, no events are posted to other apps,
and no preference, profile or system identity is changed.

The assertions cover native command role/name and child isolation, hit ownership,
actual subview containment, truncation versus Space-count geometry, both toolbar
backing-scale representations, disabled content and light/dark color resolution.
It also saves actual native light/dark component renders for appearance inspection.
The separate Settings motion check owns hover lifetime/accepted input. Compiler
and inert component checks do not establish functional browser or live VoiceOver
acceptance.
