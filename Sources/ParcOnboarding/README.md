# ParcOnboarding

ParcOnboarding owns the first-launch and Replay onboarding windows and the
browser import flow shared by setup and the menu command. It runs setup,
coordinates import work and applies the chosen setup through the browser
store. The app shell decides when to present setup, owns browser window
creation and restoration, and handles application restarts. Native import
readers and writers live behind the engine bridge. How it fits with the other libraries is in the [app architecture guide](../../docs/app-architecture.md).

## Start in the source

[OnboardingWindow.swift](OnboardingWindow.swift) holds `OnboardingWindow`
and coordinates the draft, step changes, preview choices, music and finish.
[OnboardingWelcomeView.swift](OnboardingWelcomeView.swift) draws the welcome,
[OnboardingFavorites.swift](OnboardingFavorites.swift) holds the Favorites
picker, and [OnboardingThemeEditor.swift](OnboardingThemeEditor.swift) embeds
the theme editor alongside the Space name field.
[OnboardingWindowFrame.swift](OnboardingWindowFrame.swift) holds
`OnboardingWindowFrameStep`, which previews the chosen thickness.

[BrowserImportWindow.swift](BrowserImportWindow.swift) holds the standalone
menu-import window. [BrowserImportViewController.swift](BrowserImportViewController.swift)
holds the UI shared with inline setup import, and
[BrowserImportCoordinator.swift](BrowserImportCoordinator.swift) coordinates
discovery, native import work, bookmark decisions and extension installation.
[BrowserImportNative.swift](BrowserImportNative.swift) defines the internal
import interface that `EngineBrowserImport` implements against the engine.

## Imports and host API

`ParcCore` supplies the browser store, onboarding draft, import destination
and setup models. `ParcEngine` supplies the native import operations and
extension support. `ParcKit` supplies shared controls, dialogs and appearance.
`ParcSidebar` supplies the Space theme editor, and `ParcSettings` supplies
the default-browser controller and the frame crank.

`AppDelegate` presents the package `OnboardingWindow` in first-launch or
replay mode and uses its suspend, resume and import-resume APIs. It supplies
`onComplete` to prepare or restore the browser, `onCancel` and
`onRevealCompleted` to finish the handoff, and `onRequestImportRestart` and
`onCancelImportRestart` to coordinate Safari import restarts.
[AppDelegate.swift](../Parc/AppDelegate.swift)

For menu import, `AppDelegate` constructs `BrowserImportWindow` with the
original destination and an owner validity check. It supplies the close and
restart handlers and installs the `present` closures on
`ImportedBrowserDataFailures` and `ImportedExtensionFailures` to surface
pending notices. `BrowserImportFocus` helps it decide when to return focus
to the parent window. [AppDelegate.swift](../Parc/AppDelegate.swift),
[BrowserImportFocus.swift](BrowserImportFocus.swift)

The shell also uses the package replay helpers in
[OnboardingReplayTransition.swift](OnboardingReplayTransition.swift).
`AppDelegate` supplies deferred termination and the identity, readiness,
standard-window and creation closures used to find the returning browser
window. `BrowserWindowController` supplies the page ownership checks to
`OnboardingAuxiliaryConsent` and the note read-only key path to
`OnboardingReadOnly`. [AppDelegate.swift](../Parc/AppDelegate.swift),
[BrowserWindowController+WindowLifecycle.swift](../Parc/BrowserWindowController+WindowLifecycle.swift)

## Tests

[Data](../../tests/ParcTests/Data) covers import discovery, source access,
destination mapping, bookmarks, passwords, extensions and the video handoff.
[Presentation](../../tests/ParcTests/Presentation) covers replay transitions
and setup presentation. [CommandBar](../../tests/ParcTests/CommandBar) covers
setup keyboard ownership. From the repository root, run
`swift test --filter BrowserImportDiscoveryTests` for discovery or
`swift test` for all suites.

## Behavior guides

- [First launch and replay](../../docs/onboarding.md)
- [Browser import](../../docs/browser-import.md)
- [Window frame](../../docs/window-frame.md) and [Space theme editor](../../docs/space-theme-editor.md)
