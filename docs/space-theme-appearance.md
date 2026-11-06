# Space theme editor appearance parent

SPACE13 covers the shared editor's Automatic appearance action and its parent
state. Automatic clears the application appearance override and its saved
preference. It preserves the Space's palette, color coordinate range, local
theme Undo stack, open preset page, Space/profile identities and editor lifetime.
The Light and Dark sibling controls use the same parent with Aqua and Dark Aqua.
All open editors show the parent's explicit choice, including a change made by
View → Appearance or window appearance Undo.

## Recovered contract

`4e452201e483b5480c0403a9ef8566e10515cdcb78828622ff9032b202e29547`.
The retained theme-picker evidence, recovered-components index, Swift type
table, cross-reference index and annotated-function helper answered this row.
used.

| Boundary | Recovered evidence | Result |
|---|---|---|

The earlier `theme-picker/parent-automatic-helper.asm` and
`editor-appearance-reinit.asm` names suggested a broader reset. Their functions
are not the Automatic button's parent. Likewise the real `didForceAppearance`
three appearance buttons do not send that action. The previous Parc button
wiring had incorrectly attributed that reducer to these controls.

## Parc ownership and compatibility

`SpaceThemeEditorView.onSetAppearance` delegates to its owner after finishing
any active color gesture. It does not call theme preview/commit for the parent
choice and does not replace `SpaceThemeEditorState`. A KVO observation of the
explicit `NSApplication.appearance` refreshes every editor's selected control.
Observing effective appearance alone would miss Automatic ↔ Light when the
system already uses Light. The observation holds the editor weakly and retires
with it.

The existing-Space owner checks the original editor and Space identities.
The new-Space owner checks the original creation session and editor. Both apply
the existing `AppAppearance` helper and register a changed name through the
original browser window's existing `Update Appearance` Undo route. First-launch
setup uses the same app parent without creating a browser-window Undo owner.
The native app override and `parc.appAppearance.v1` preference remain owned by
`AppAppearance`; Automatic removes the preference even when the native override
was already cleared. No current key-window lookup chooses a different browser.

Since November 2, replay setup enables the app appearance controls. Replay
shows its choice with `AppAppearance.preview` without saving it; Finish saves
it, and an early close shows the saved choice again unless one made elsewhere
replaced it. Its color edits preview live on the originating Space until Finish keeps them
or an early close restores the original (see `onboarding.md`).

The saved `SpaceTheme.Appearance` field, decoder and renderer remain intact for
existing documents. Opening an editor or changing its application appearance
never migrates or overwrites that stored theme. The unused palette-mutation
method formerly called by these buttons has been removed. This row does not
change the material/text renderer, pointer behavior, physical haptics or theme
animation. Cross-popover palette Undo remains SPACE14; using the already-built
application appearance Undo path does not claim that row.

## Checks and delivery

`scripts/test-theme-appearance.sh` compiles the actual AppKit editor and
`AppAppearance` with an isolated preferences suite. Its inert controls cover
native nil reset and preference removal, repeated and already-nil reset,
Light/Dark siblings, cross-editor and external-parent updates, saved-choice
restoration, preservation of themes/preset page/local Undo and Redo, observer
lifetime and replay refusal. It does not open a visible window or load an engine.

`scripts/test-theme-appearance.sh` passes 72 assertions and
`scripts/test-theme-editor.sh` passes 60 model assertions, including existing
persisted forced light/dark themes. Whole-module Swift typecheck and the final
SIL pass succeed with warnings as errors and zero diagnostics, using Apple
Swift 6.4 from `/Applications/Xcode.app/Contents/Developer`. Source-identical
reconciliation includes the intervening Extensions deliveries without rerunning
their checks. Compiler, component and review receipts are retained under
`work/spaces-profiles-checks/space13`; runtime browser acceptance is not claimed.
Independent `space13_review` cleared the complete finished source with no
blocking findings. Its receipt records the exact reviewed patch and source
hashes; subsequent delivery-ledger edits and source-identical reconciliation
do not change that source.
