# Dock tile plug-in

`ParcDockTile` is the Objective-C AppKit plug-in that draws the selected Parc
icon in the Dock, including when the browser is closed. The app's icon picker
and preference writer live in
[ParcSettings](../ParcSettings/AppIconController.swift). The plug-in reads
the result and updates the Dock tile. How it fits with the other libraries is in the [app architecture guide](../../docs/app-architecture.md).

## Entry point and app connection

[ParcDockTile.m](ParcDockTile.m) implements `NSDockTilePlugIn`.
`setDockTile:` finds the enclosing Parc app bundle, observes its
`org.parc.Browser.appIconChanged` distributed notification, and refreshes the
tile. The notification is scoped to the app bundle's resolved path. When the
Dock releases the tile, the plug-in removes its observer.

`refreshIcon` reads the selection from `Parc/app-icon.json` in the user's
Application Support folder. It validates the selection against the
`AppIcons/catalog.json` bundled with the app and falls back to Original
when there is no valid selection. It reads the matching ICNS from the same
bundle and assigns a scaled image view to the tile.

## Build and dependencies

[package-app.sh](../../scripts/package-app.sh) calls
[build.py](../../scripts/build.py). The Python packager compiles the source with
Clang and AppKit into `Contents/PlugIns/ParcDockTile.plugin`, with
`ParcDockTile` as its principal class. The app's `NSDockTilePlugIn` plist
entry points macOS at that bundle. SwiftPM builds the picker code in
`ParcSettings`. Packaging builds the plug-in separately.

## Checks and guides

The [icon packaging suite](../../tests/Packaging/test_icons.py) checks the
plug-in's bundle entry, placement and signing alongside the icon resources.
The [app test target](../../tests/ParcTests/README.md) covers the picker in
[Data](../../tests/ParcTests/Data) and icon identity in
[Presentation](../../tests/ParcTests/Presentation). Run from the repository root:

```sh
python3 -m unittest discover -s tests/Packaging -p test_icons.py
swift test --filter IconSettingsTests
swift test --filter AppIconControllerTests
```

The picker guide describes the interaction tests and the controller that
writes the preference file. See [app icon picker](../../docs/app-icon-picker.md),
[icon availability](../../docs/app-icon-availability.md) and
[packaging](../../tests/Packaging/README.md) for the icon behavior and bundle
layout.
