# Core library tests

`ParcCoreTests` exercises the browser models, stores, persistence and decision
logic in [ParcCore](../../Sources/ParcCore). Its target depends on the core
library and shared test support. The AppKit views and engine-facing app code
are covered in [ParcTests](../ParcTests/README.md) and
[ParcNativeTests](../ParcNativeTests/README.md). The rules every test follows, and the kinds of test that are banned, are in the [testing guide](../../docs/testing.md).

## Where the suites live

| Folder | Look here for |
| --- | --- |
| [Browser](Browser) and [Favorites](Favorites) | Tab lookup, Favorite splits and saved-tab reset decisions |
| [Windows](Windows) and [Sidebar](Sidebar) | Window continuity, splits, Peek, Space and sidebar state, archive and undo |
| [CommandBar](CommandBar) | Actions, commands, folders, history, keyboard, settings and text |
| [Data](Data) | Store, settings, import, export and update rules |
| [Engine](Engine) | Foundation-side parsing of relaunch arguments and native download records |
| [Notes](Notes) and [Easels](Easels) | Editing and document formats, file handling, navigation, board behavior and persistence |
| [Capture](Capture) | Capture destinations, frames and related decisions |
| [Presentation](Presentation) | Membership, onboarding, themes and updates at the model level |

## Dependencies and helpers

[Package.swift](../../Package.swift) declares dependencies on `ParcCore`
and [ParcTestSupport](../ParcTestSupport/README.md). Tests import the core
module with `@testable import` as needed and can use
[TestDefaults](../ParcTestSupport/TestDefaults.swift) to isolate preferences.

[Support/Check.swift](Support/Check.swift) records Swift Testing issues.
Feature-specific setup lives alongside its tests. For example,
[NoteFileTestSupport.swift](Notes/NoteFileTestSupport.swift) holds the core
Notes file fixtures and their isolated settings. The AppKit-oriented
`IsolatedNoteFiles` and `ControlClick` helpers live in
[ParcTests/Support](../ParcTests/Support) and belong to that target.

## Bundled fixtures

[Package.swift](../../Package.swift) processes the [Notes emoji fixture](Notes/Fixtures/emoji.json)
and copies the [Easel round-trip data](Easels/Fixtures/EaselRoundTrip) and
[Arc sidebar import fixtures](Resources/ArcSidebar). SwiftPM exposes those
resources through `Bundle.module`. The Easel round-trip and Arc sidebar
import suites use their copied directories by name.

## Run the tests

Run from the repository root:

```sh
swift test
swift test --filter EaselRoundTripTests
swift test --filter NativeRelaunchTests
```

See the [testing guide](../../docs/testing.md),
[split groups](../../docs/split-groups.md),
[Notes formats](../../docs/notes-format.md),
[local Easel editing](../../docs/easels.md) and
[browser import](../../docs/browser-import.md) for the package workflow and
the behavior behind these suites.
