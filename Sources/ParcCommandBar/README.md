# ParcCommandBar

ParcCommandBar owns the address editor, command palette, resident start-page bar,
recent-tab switcher, and shortcut UI. It turns edits and gestures into selections
or requests. The browser window supplies the current page and Profile, owns the
start page, and carries out navigation, tab changes and app commands in their
original context. How it fits with the other libraries is in the [app architecture guide](../../docs/app-architecture.md).

## Start in the source

[CommandBar.swift](CommandBar.swift) holds `CommandBar`, the in-window session
and host for the field and result list. The same session serves the full palette,
compact address editor and resident bar. Start in
[CommandBarEditState.swift](CommandBarEditState.swift) for editing state,
[CommandBarScopeEditing.swift](CommandBarScopeEditing.swift) for scope changes
or [CommandBarSubmission.swift](CommandBarSubmission.swift) for submission.

[CommandBarRanking.swift](CommandBarRanking.swift) combines result candidates.
[CommandBarTitleSearch.swift](CommandBarTitleSearch.swift) builds and queries the
local tab and history title index. [CommandBarNotes.swift](CommandBarNotes.swift)
adapts note matches, and [CommandResultsTable.swift](CommandResultsTable.swift)
handles the result list's keyboard, pointer and scrolling behavior.

[RecentTabSwitcher.swift](RecentTabSwitcher.swift) manages the switcher
session and [RecentTabSwitcherView.swift](RecentTabSwitcherView.swift) draws
its rows. [ShortcutsSettingsView.swift](ShortcutsSettingsView.swift) holds the
shortcut settings pane. [ShortcutEssentialsWindow.swift](ShortcutEssentialsWindow.swift)
and [ShortcutPriorityHintView.swift](ShortcutPriorityHintView.swift) cover
shortcut discovery outside Settings.

## Imports and host API

`ParcCore` supplies tabs, history, shortcut bindings and command records.
`ParcEngine` supplies the native omnibox, classified navigation, extension
actions and page handles. `ParcKit` supplies shared controls and presentation.
`ParcNotes` supplies the searchable note library and note artwork.

The browser window creates `CommandBar`, presents or focuses it, reconciles
its candidates as the context changes, and dismisses it. It supplies the
documents source, note library, captions, removed history URLs and the data for
`CommandBarTitleIndexCache`, then uses `onBuilt` to deliver the index. It
supplies owner validation, focus restoration and dismissal callbacks, and the
keyboard Sidebar session's movement, commit and query-state callbacks.
[BrowserWindowController+CommandBar.swift](../Parc/BrowserWindowController+CommandBar.swift),
[BrowserWindowController+StartPage.swift](../Parc/BrowserWindowController+StartPage.swift)

That same window supplies input, classified navigation and tab selection,
including background and split variants. It validates and performs Space,
folder, Favorite, typed and split actions, and handles pane commands, document
opening, Archive restoration, muting, copy, password and search settings, and
listing and launching extension actions. The split picker also supplies
submission and rejection callbacks for its pending destination.
[BrowserWindowController+CommandBar.swift](../Parc/BrowserWindowController+CommandBar.swift),
[BrowserWindowController+Splits.swift](../Parc/BrowserWindowController+Splits.swift)

The browser window gives `RecentTabSwitcher` its items and favicon requests,
checks that its source stays current, and handles completion and tab close.
It supplies the Essentials window's owner and command checks, command
dispatch, Escape and View All actions, and the priority hint's edit and
dismiss actions. Settings embeds the package `ShortcutsSettingsView`.
The window also supplies dismiss and refresh actions to
`ShortcutTooltipDiscovery` and native availability checks to
`TaskManagerRoute`.
[BrowserWindowController+TabSelection.swift](../Parc/BrowserWindowController+TabSelection.swift),
[BrowserWindowController+PageTools.swift](../Parc/BrowserWindowController+PageTools.swift),
[BrowserWindowController+Toolbars.swift](../Parc/BrowserWindowController+Toolbars.swift),
[BrowserWindowController.swift](../Parc/BrowserWindowController.swift),
[SettingsWindow.swift](../ParcSettings/SettingsWindow.swift)

## Tests

[CommandBar](../../tests/ParcTests/CommandBar) covers sessions, editing, scopes,
ranking, submissions, result presentation, switching and shortcuts.
[Notes](../../tests/ParcTests/Notes) covers note matching, and
[Windows](../../tests/ParcTests/Windows) includes Archive preview and command-bar
focus coverage. Run `swift test --filter CommandBarEditTests` from the
repository root for one suite, or `swift test` for all suites.

## Behavior guides

- [Command bar](../../docs/command-bar.md), [field and results](../../docs/command-bar-results.md) and [search scopes and commands](../../docs/command-bar-scopes.md)
- [Start page](../../docs/start-page.md), [keyboard navigation](../../docs/keyboard-navigation.md) and [recent-tab switcher](../../docs/tab-switcher.md)
