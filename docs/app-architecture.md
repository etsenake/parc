# App architecture

Parc's macOS app is the Swift package at the repository root. The browser engine
sits behind an Objective-C bridge; everything a person sees and every saved
piece of state is Swift, split into libraries that each own one part of the
product. This guide explains how those libraries are layered, how a lower one
reaches a higher one without importing it, which declarations may cross a
library boundary and where new code belongs. The engine side is described in
the [engine architecture](../Engine/README.md) and
[how Parc changes Chromium](chromium-seams.md); how to test all of this is in the
[testing guide](testing.md).

## The libraries

From the bottom up, each library imports only libraries below it:

| Library | Owns | Imports |
|---|---|---|
| [ParcCore](../Sources/ParcCore/README.md) | Browser state and persistence, the models behind Notes, Easels, the command bar, captures and import, and routing. No AppKit, no engine. | System frameworks only |
| [ParcKit](../Sources/ParcKit/README.md) | Shared controls, dialogs, tooltips, toasts, theme colours, animation helpers and the keyboard shortcut model. | ParcCore, ParcEngine |
| [ParcNotes](../Sources/ParcNotes/README.md) | The Notes editor, its blocks and embedded web pages. | Core, Kit |
| [ParcEasels](../Sources/ParcEasels/README.md) | Easel boards, their canvas, tools and exports, built on the Notes editor. | Core, Kit, Notes |
| [ParcLibrary](../Sources/ParcLibrary/README.md) | The Library: downloads, captures, media and archive pages. | Core, Kit, Notes, Easels |
| [ParcCommandBar](../Sources/ParcCommandBar/README.md) | The command bar, its scopes and results. | Core, Kit, Notes |
| [ParcSidebar](../Sources/ParcSidebar/README.md) | The sidebar, Spaces, folders and the toolbar controls it hosts. | Core, Kit, Notes, Easels, Library, CommandBar |
| [ParcSettings](../Sources/ParcSettings/README.md) | The settings window and app preference stores. | Core, Kit, Notes, CommandBar, Sidebar |
| [ParcOnboarding](../Sources/ParcOnboarding/README.md) | Setup, browser import and membership. | Core, Kit, Sidebar, Settings |
| [Parc](../Sources/Parc/README.md) | The app delegate, browser windows and their splits, Peek, the start page, popups and the hooks below. | Every library above, plus Sparkle |

Every app library also links [ParcEngine](../Sources/ParcEngine/README.md), the
bridge to the engine. [ParcMain](../Sources/ParcMain/README.md) is the
executable: it only calls the launch function, so tests load all of the app's
code without starting the app. The helper executables
([ParcHelper](../Sources/ParcHelper/README.md),
[ParcDockTile](../Sources/ParcDockTile/README.md) and
[ParcRestart](../Sources/ParcRestart/README.md)) are packaged beside the app.

The order is enforced by the manifest: a library can only import what
`Package.swift` lists as its dependency, and the list never points upward. A
cycle is a build error, not a review comment.

## Calling up without importing

Sometimes lower code needs a feature that lives higher up. Notes must draw an
Easel embedded in a note, but Easels are built on Notes. The lower library
declares a small protocol or an injected closure describing what it needs, and
the higher library supplies it:

- **Easel blocks in notes.** ParcNotes declares `NoteBoardProviding` (with
  `NoteBoardHost` and `NoteBoardPages`) in `NoteBlockViewFactory`. ParcEasels
  implements it as `NoteEaselProvider`, and `AppDelegate` registers it at launch
  by setting `NoteBlockViewFactory.boards`.
- **Window actions.** ParcNotes declares `NoteWindowActions` for the window
  commands an editor needs, and ParcEasels extends it as `EaselWindowActions`.
  `BrowserWindowController` conforms in Parc.
- **The Library's Spaces page.** ParcLibrary declares `LibrarySpacesPage`, and
  `LibraryView` takes the page through its initializer. ParcSidebar's
  `SpaceManagerView` is that page.
- **Sidebar drags.** ParcSidebar declares `SidebarMoveOwner` for whoever owns a
  drag in progress; `BrowserWindowController` conforms in Parc.
- **Settings buttons.** ParcSettings takes a `SettingsWindow.Actions` value of
  closures for the buttons that act on the whole app. Parc builds it once as
  `AppDelegate.settingsActions`.

Keep these hooks narrow: name what the lower code needs, not the higher type
that happens to provide it. Default an injected closure or provider to doing
nothing, so a lower library and its tests work without the app.

## What may cross a boundary

Declarations are `internal` unless another library uses them; mark one
`package` only then. Swift requires `open` for a class that another library
subclasses, and `public` for the members it overrides, its designated
initializers and the types those name, so use `open` and `public` only there.
A public view or window class also declares `Sendable`: Swift infers that for
main-actor classes only inside their own library, and subclasses elsewhere
capture `self` in timer and notification closures.

A memberwise or `OptionSet` initializer is always internal, so a struct built
in another library needs an explicit `package init`. Tests reach internal
declarations through `@testable import`, so a test never needs `package`.

## Imports and rebuild time

Each file imports exactly the libraries it uses. This keeps rebuilds fast as
well as tidy. A Swift build recompiles every file that directly imports a
library whenever that library gains or changes a declaration, even a private one
no other file can see; both of SwiftPM's build engines do this. Changing code inside an existing function body
recompiles only that file. Files that reach the library only through another
library are left alone. So an unused import makes the file recompile for every
declaration edit in that library, and an unused import of `Parc` in a test makes
it recompile for every new declaration anywhere in the app shell.

The same reasoning favours small foundations: a declaration edit in ParcCore or
ParcKit recompiles most of the app because most of the app genuinely uses them.

## Where new code goes

Put code in the lowest library that can own it:

- Logic and state with no AppKit go in ParcCore, where they are fastest to
  build and test.
- A control, dialog or visual rule used by more than one feature goes in
  ParcKit.
- Feature code goes in its feature's library, even when only Parc calls it.
- Parc keeps what genuinely spans features: windows, splits, Peek, app
  lifecycle and the hooks that connect the libraries.

If a type is needed below where it lives, move it down when it has no
higher dependencies, or add a hook as above. Never import upward, and never
copy a type into two libraries.

## The engine boundary

App code reaches the engine only through ParcEngine, whose headers come from
`Engine/ParcNative`. Package builds never need an engine binary: debug and test
builds weak-link a text stub of the engine's exports, and tests link
`ParcEngineDoubles` instead of the engine. Engine components that build without
Chromium are compiled into the `ParcNative` library for their own tests. The
[development setup guide](development-setup.md) covers regenerating the stub
and the manifest's compiler settings; Chromium itself changes only within the
[Chromium boundary](../AGENTS.md#chromium-boundary).
