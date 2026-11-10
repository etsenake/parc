# Space theme editor appearance parent

Automatic clears the application's appearance override and saved preference.
Light and Dark set Aqua and Dark Aqua through the same parent. These controls
preserve the Space palette, color range, palette Undo stack, preset page and
editor identity. All open editors reflect the application's explicit choice,
including changes from View → Appearance and appearance Undo.

## Parc ownership and compatibility

`SpaceThemeEditorView.onSetAppearance` finishes the active color gesture and
then delegates to its owner. It neither commits a palette edit nor replaces
`SpaceThemeEditorState`. A weak KVO observation of explicit
`NSApplication.appearance` updates the selected control. Observing effective
appearance alone would miss Automatic ↔ Light when the system already uses
Light.

Existing-Space and new-Space owners validate their original editor/session.
`AppAppearance` owns the native override and `parc.appAppearance.v1` preference.
A changed explicit name registers with the original window's Update Appearance
Undo route; Automatic removes the preference even if the override was already
nil. First launch uses the same application parent without a browser-window Undo
owner. No current-key-window lookup redirects the operation.

Onboarding replay previews application appearance without saving it. Finish
saves the chosen value; early close restores the saved value unless another
owner has replaced it. Theme edits likewise preview on the originating Space
until Finish commits them or close restores the original. See
[onboarding](onboarding.md).

The saved `SpaceTheme.Appearance` field remains intact for existing documents.
Opening an editor or changing application appearance must not migrate or
rewrite that stored theme. Palette Undo is documented separately in
[theme Undo](space-theme-undo.md).

## Checks and delivery

`scripts/test-theme-appearance.sh` compiles the actual AppKit editor and
`AppAppearance` with isolated preferences. It covers nil reset, preference
removal, Light/Dark siblings, external-parent updates, saved-choice restoration,
palette/preset/Undo preservation and observer lifetime. Theme model tests and
whole-module Swift checks remain applicable. Compiler/component results do not
establish browser runtime or physical display acceptance.
