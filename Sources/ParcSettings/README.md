# ParcSettings

ParcSettings builds the native Settings window and owns app preference
controllers, including the app icon, local membership card and window-frame
adjustment. It edits application, Space and Profile preferences through their
owners. The app shell opens browser-hosted settings pages, handles window
lifecycle and starts onboarding replay. How it fits with the other libraries is in the [app architecture guide](../../docs/app-architecture.md).

## Start in the source

[SettingsWindow.swift](SettingsWindow.swift) holds `SettingsWindow`, the
pane list, the General and Spaces controls, and the Settings window's original
Space and Profile context. [SettingsNavigation.swift](SettingsNavigation.swift)
tracks pane navigation, and [SettingsFocus.swift](SettingsFocus.swift) handles
focus across pane changes and sheets. Shared row and group controls live in
[SettingsPresentation.swift](SettingsPresentation.swift).

[LinkRoutingSettings.swift](LinkRoutingSettings.swift) holds
`LinksSettingsView` and the `LinkRoutingWindow` editor for Air Traffic Control.
[MembershipCardSettingsView.swift](MembershipCardSettingsView.swift) owns the
local membership card pane and its export UI. [IconSettingsView.swift](IconSettingsView.swift)
presents the picker, and [AppIconController.swift](AppIconController.swift)
supplies the active icon and artwork.

[WindowFramePreferences.swift](WindowFramePreferences.swift) holds the saved
frame thickness and temporary preview. [WindowFrameCrankView.swift](WindowFrameCrankView.swift)
holds the crank UI, with input and sound feedback in
[WindowFrameCrankFeedback.swift](WindowFrameCrankFeedback.swift).

## Imports and host API

`ParcCore` supplies browser state, routing rules, and preference models.
`ParcEngine` supplies native search and download preferences. `ParcKit`
supplies shared UI, `ParcNotes` supplies the note folder picker and preferences,
`ParcCommandBar` supplies the shortcuts pane, and `ParcSidebar` supplies
preview settings, Space data-sharing UI and Profile removal.

The app shell creates `SettingsWindow` and uses its package pane selection,
refresh, close and context APIs. `AppDelegate` supplies `SettingsWindow.Actions`
for replay availability, starting replay and adjusting the frame. The browser
window and app delegate supply the Profile page, More Settings and Space
deletion handlers for their respective Settings windows. The browser window
also uses `onSheetEnded` to resume a pending close.
[AppDelegate.swift](../Parc/AppDelegate.swift),
[BrowserWindowController+PageTools.swift](../Parc/BrowserWindowController+PageTools.swift)

The browser window and onboarding's frame step each supply `WindowFrameCrankView`
with preview, event and finish callbacks. The shell applies the browser
preview and saves the preference; onboarding follows the preview and updates
its draft. `DefaultBrowserController` is shared by Settings and onboarding.
[BrowserWindowController+ChromeLayout.swift](../Parc/BrowserWindowController+ChromeLayout.swift),
[OnboardingWindowFrame.swift](../ParcOnboarding/OnboardingWindowFrame.swift),
[DefaultBrowserController.swift](DefaultBrowserController.swift)

The app shell also consumes the package controllers for frame, toolbar, pinned
section, quit warning, webpage dragging, Shared Quote and website theme
preferences. The browser window configures the pane's `WebpageWindowGrabber` with owner
validity and event eligibility. The app's `SharedQuoteController` supplies
selection validation, scheduling and display to `SharedQuoteSession`.
[WebpageWindowDragging.swift](WebpageWindowDragging.swift),
[BrowserWindowController+Toolbars.swift](../Parc/BrowserWindowController+Toolbars.swift),
[SharedQuotePreferences.swift](SharedQuotePreferences.swift),
[SharedQuotes.swift](../Parc/SharedQuotes.swift)

## Tests

[Data](../../tests/ParcTests/Data) covers the Settings window, icons and default
browser. [LinkRouting](../../tests/ParcTests/LinkRouting) covers routing edits,
[Presentation](../../tests/ParcTests/Presentation) covers the membership card,
website theme and toolbar, and [Windows](../../tests/ParcTests/Windows) covers
the frame and dragging. [Notes](../../tests/ParcTests/Notes),
[Sidebar](../../tests/ParcTests/Sidebar) and [CommandBar](../../tests/ParcTests/CommandBar)
add Shared Quote, pinned header and Settings close-command checks. Run
`swift test --filter SettingsNavigationTests` or `swift test` from the repository root.

## Behavior guides

- [Settings](../../docs/settings.md), [pane presentation](../../docs/settings-presentation.md) and [Profile removal](../../docs/settings-profile-removal.md)
- [Air Traffic Control](../../docs/routing-interaction.md), [app icons](../../docs/app-icon-picker.md) and [membership card](../../docs/settings-membership-card.md)
- [Window frame](../../docs/window-frame.md) and [Replay onboarding](../../docs/onboarding.md#general--replay-onboarding)
