# Testing

Parc's tests are unit tests in the Swift package at the repository root. Each
one checks a single behaviour in isolation, runs in milliseconds and needs no
engine, no window on screen and none of your data. This guide covers how to run
them, the rules every test follows, the kinds of test that are banned and why,
and how production code exposes the seams tests use. How the code is organized
is in the [app architecture guide](app-architecture.md).

## Running tests

```sh
swift test                              # build what changed, run every suite
swift test --filter EaselIdleSleepTests # one suite
swift build --build-tests               # compile only
```

Suites run in parallel in one process. Builds are incremental and cached in
`.build`: after an edit inside a function body only that file recompiles. A new
or changed declaration recompiles every file that imports its library directly,
which is why each file imports only what it uses (see
[imports and rebuild time](app-architecture.md#imports-and-rebuild-time)).

The test targets:

- [ParcCoreTests](../tests/ParcCoreTests/README.md) tests ParcCore, which has
  no AppKit, so most logic belongs here.
- [ParcTests](../tests/ParcTests/README.md) tests the app libraries, with a
  `@testable import` of each library a test uses and no other.
- [ParcNativeTests](../tests/ParcNativeTests/README.md) tests the Chromium-free
  engine components with Objective-C XCTest cases (see
  [native tests](#native-tests)).
- The `EngineFacade*Tests` targets compile the app's engine facade against test
  doubles of the native classes, one set of doubles per target, so the
  old-engine target fails to link if the facade names a class older engines lack.

Shared helpers live in [ParcTestSupport](../tests/ParcTestSupport/README.md)
and `tests/ParcTests/Support`. Python `unittest` suites exist only for Python
tooling: `tests/BuildTools` (build and release scripts), `tests/Site` (the
website, also run by GitHub CI), `tests/Documentation` (the docs checker) and the
release tooling suites beside them. Checks that need a completed engine build stay
outside `swift test`, each in its own `tests/` folder with a README and runner:
FairPlay, error pages, the browser import readers, helper routing, platform
codecs and the native runtime harness.

## What a test looks like

Write one behaviour per `@Test`, named as a plain sentence in camelCase, and
build only the fixture that behaviour needs. Check with `#expect`, and use
`try #require` when later lines depend on a value. Give inputs to a
parameterized `@Test(arguments:)` instead of looping inside a test, so each case
runs and reports on its own. Randomized tests keep a fixed seed.

Keep logic in models, stores and pure functions so it can be tested without any
view. Put a test in the lowest target that can reach the code under test, in a
folder named for its feature area.

Keep test files small: one suite per file, named after the suite, usually 150
to 300 lines and never more than 500. When a suite grows past that, split it by
behaviour group into sibling suites that share the original name as a prefix,
and move helpers they share into a `<Name>Support.swift` file beside them.
Nest helpers in the suite or make them `private`, because each target is one
module.

Tests run in parallel, so they share no mutable state. Give each test its own
temporary directory and a `TestDefaults` instance from ParcTestSupport, which
keeps preference values in memory and clears its domain on release. Give tested
WebKit views a nonpersistent website data store. Mark a test `@MainActor` only
when the code needs the main actor. Test fixtures are resources on the test
target (`resources:` in the manifest), loaded through `Bundle.module`.

## Banned

Each of these made the old suite slow, flaky, dependent on the machine it ran
on, or silently untrustworthy. None of them is allowed in any target.

**Putting a window on screen, or waiting for drawing or animation.** On-screen
windows fight over focus when tests run in parallel, need a logged-in display
and turn a millisecond check into a wait. Construct and lay out a view directly.
When responder or key handling needs a window, host the view in a borderless
window that is never ordered front.

**Waiting on real time.** No `sleep`, no polling loops, no spinning the run loop
until something happens, no real timers. They make tests slow and timing
dependent. Inject time through Swift's `Clock` protocol or a scheduler and
advance it in the test.

**Replacing methods at runtime.** No swizzling, no `method_exchangeImplementations`
or `class_replaceMethod`, and no adding methods to AppKit or app classes with
`imp_implementationWithBlock`. A swapped method changes every caller in the
process, including tests running in parallel, and hides the real dependency.
Give the production code an injectable environment instead, whose default makes
exactly today's calls, as the picture-in-picture panel does for its cursor,
event monitors and window lookups.

**Overriding process-wide state.** No writing to `UserDefaults.standard`,
swapping `NSApp`'s delegate, changing environment variables, replacing shared
singletons or posting to the global notification center to steer the code under
test. Pass the dependency in. Mark a suite `.serialized` only when the code
touches process-wide state that genuinely can't be injected.

**Touching your real data.** A test never reads or writes your preferences, your
browser profiles or the real Parc Notes folder in Documents. Besides corrupting
your data, a test touching Documents on a fresh Mac waits forever on macOS's
privacy prompt. Anything built without a `files:` argument uses
`NoteFiles.shared`, so pass `IsolatedNoteFiles.make()` from
`tests/ParcTests/Support`.

**Simulated clicks.** Never call `performClick(_:)` on a control or
`performClose(_:)` on a window. Both spin a nested event-tracking run loop that,
with tests in parallel, can stop the main run loop and end the test process
silently with no summary. Call `sendClick()` from
`tests/ParcTests/Support/ControlClick.swift`, call a menu item's action on its
target, and give a window double a `performClose` that asks its delegate.

**Testing source text.** Never assert that source files contain particular
code: no matching lines, regular expressions or call counts over Swift or
Objective-C files. Such a test passes while the behaviour is broken and fails on
harmless rewording. Test what the code does.

**Script-driven test harnesses.** App behaviour is tested only by suites in the
package. No shell or Python runner that compiles fragments of the app, launches
it or scrapes its output to decide pass or fail. Python tests exist only for
Python tooling.

**Launching the app.** This suite holds unit tests only; end-to-end checks of
the running app would be UI tests, which it doesn't contain. `ParcMain` only
calls the launch function so that tests can load the app's code without it.

**Fixture paths from `#filePath`.** They break when the package moves or builds
from an archive. Declare fixtures as resources and load them from
`Bundle.module`.

**Unused imports.** A test imports only the libraries it uses. An extra import
makes the file recompile for every declaration edit in that library.

## Seams in production code

A seam is how production code lets a test supply a dependency. Add one as a
defaulted initializer parameter or a small environment struct whose default is
exactly today's behaviour, so the app's code paths are unchanged:

- Time comes from a `Clock` or scheduler.
- Preferences come from a `UserDefaults` instance, which tests replace with
  `TestDefaults`.
- Files come from a `NoteFiles` or a directory URL.
- AppKit calls that would touch the screen, the cursor or global event
  monitors go through an environment value.
- A lower library reaches a higher one through a hook (see
  [calling up without importing](app-architecture.md#calling-up-without-importing)).

Never give production code a test-only branch, flag or global switch.

## Native tests

ParcNativeTests uses Objective-C XCTest cases built on `ParcNativeTestCase`.
Check with `PARC_CHECK` or the suite's `Check(condition, message)`; both stop the
test at the first failure. Name the classes with a `Tests` suffix and filter by
class, for example `swift test --filter PageHostTests`. Never edit an engine
input for a test.

Parc's native presenters reach windows and time through two protocols in
`page_host.h`. `PCNativePresentation` covers sheets, child windows, ordering,
visibility and popovers; `PCNativeScheduling` covers uptime, dates, timers,
run-loop and main-queue hops and animation groups. Each presenter starts with
the system implementation, which makes exactly the AppKit, Foundation and GCD
calls. A test hands it the test case's offscreen doubles,
`ParcNativePresentation()` and `ParcNativeScheduler()`, which keep sheets,
children and visibility as state and never order a window on screen. Check that
state with the `ParcNative…` helpers in `ParcNativeWindows.h`, such as
`ParcNativeAttachedSheet`.

Native tests never wait in real time. `ParcNativeAdvance(seconds)` moves the test
clock, fires the timers that fall due and then settles pending work.
`ParcNativeSettle()` handles only the work that is already pending. Animation
groups run at zero duration.

Warnings are errors in every target (`treatAllWarnings`), matching the release
compile.
