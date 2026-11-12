# Native Settings presentation check

Run `python3 tests/SettingsPresentation/check.py /absolute/output-directory`
with full Xcode selected. It compiles the actual production group, section
heading, badge, command row, profile row and pill button with the existing
native LayoutView. No browser is created, no events are posted to other apps,
and no preference, profile or system identity is changed.

The assertions cover native command role/name and child isolation, hit ownership,
actual subview containment, borderless rounded groups, profile-name truncation
against an unclipped Space count, profile-row activation, removal relabeling,
disabled content and light/dark color resolution. It also saves actual native
light/dark component renders for appearance inspection. The separate Settings
motion check owns hover lifetime and accepted input.

The back and forward history model has its own check:

    xcrun swiftc -warnings-as-errors -parse-as-library \
      Sources/ParcApp/SettingsNavigation.swift tests/SettingsNavigation/Tests.swift \
      -o build/settings-navigation && build/settings-navigation

Follow [AGENTS.md](../../AGENTS.md) when choosing checks.
