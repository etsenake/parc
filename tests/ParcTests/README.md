# App library tests

`ParcTests` exercises the Swift app shell and feature libraries, including
AppKit view behavior, window actions and the way features work together. It
imports those libraries directly, with no dependency on the launcher. Model
and persistence behavior that belongs entirely to `ParcCore` lives in
[ParcCoreTests](../ParcCoreTests/README.md). The rules every test follows, and the kinds of test that are banned, are in the [testing guide](../../docs/testing.md).

## Where the suites live

| Folder | Look here for |
| --- | --- |
| [Windows](Windows) | Window commands, splits, Peek, archive previews and navigation controls |
| [LinkRouting](LinkRouting) | Link routing while editing text |
| [Sidebar](Sidebar) | Sidebar controls, previews, drag and undo |
| [CommandBar](CommandBar) | Command admission, shortcut bindings and the recent-tab switcher |
| [Notes](Notes) and [Easels](Easels) | Editors, local document presentation and embedded page pools |
| [Capture](Capture) | Capture editing, capture Library and the Mini Player |
| [Data](Data) | Import, application termination, archiving and other app data flows |
| [Presentation](Presentation) | Toolbars, app icons, themes, membership and update presentation |

## Dependencies and helpers

[Package.swift](../../Package.swift) links the app libraries and
[ParcEngineDoubles](../ParcEngineDoubles/README.md), which supplies native
class symbols and fixtures for tests that exercise engine-facing UI.
Tests can reach internal declarations with `@testable import`.

[Support](Support) holds helpers local to this target.

- [IsolatedNoteFiles.swift](Support/IsolatedNoteFiles.swift) builds `NoteFiles`
  with a unique temporary folder, test defaults, configurable clock and
  workers, and a trash mover that refuses to touch the real Trash.
- [ControlClick.swift](Support/ControlClick.swift) provides `sendClick()`.
  It sends the action directly for ordinary controls and honors custom
  `performClick` overrides.
- [TestEaselCanvas.swift](Support/TestEaselCanvas.swift) constructs an
  `EaselCanvasView` with test preferences.
  [Check.swift](Support/Check.swift) records Swift Testing issues with the
  caller's source location.
- [ParcTestSupport](../ParcTestSupport/README.md) provides `TestDefaults`, the
  in-memory preference store shared with the core suites.

## Bundled fixtures

[Package.swift](../../Package.swift) declares these resources on the test
target. Swift tests find them in `Bundle.module`.

| Folder | Resources |
| --- | --- |
| [Notes](Notes) and [Easels](Easels/Fixtures) | Notes fonts, the Notes emoji catalog and Easel fonts |
| [Presentation](Presentation/Fixtures) | App icons, the native ICNS, membership cards, theme-editor fixtures and theme textures |
| [Capture](Capture) | Capture fixtures and Library fixtures |
| [Windows](Windows/Fixtures) | Navigation control and split-view fixtures, plus the Windows emoji catalog |
| [CommandBar](CommandBar) | Command bar and recent-switcher fixtures |
| [Sidebar](Sidebar) | Sidebar preview, chrome and plus-menu fixtures |
| [Data](Data/Fixtures) | Arc sidebar import, scripting and Site Control Center fixtures |

## Run the tests

Run from the repository root:

```sh
swift test
swift test --filter SoftwareUpdateBannerTests
```

Write a focused test for an observable behavior in the lowest target that can
exercise it.

See the [testing guide](../../docs/testing.md) for the package workflow and the guides for [windows](../../docs/windows-lifecycle.md),
[Notes](../../docs/notes.md), [capture](../../docs/page-capture.md) and
[the command bar](../../docs/command-bar.md) for the behavior under test.
