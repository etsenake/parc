# Native external split-drop components

Read [the working contract](../../AGENTS.md) before running checks.

`swift test --filter ExternalSplitDropTests` checks the durable model transaction
using a temporary session and a failed atomic replacement.

`swift test --filter ContentDropRouterTests` runs the router cases.
`python3 tests/NativeContentDrop/run_components.py` runs the Swift session
fixture. Its optional `--receipt /absolute/path.json` records the inputs and
output.

The router component compiles the production Objective-C++ source and drives its
admission, update, prepare, commit and teardown methods through injected
`NSDraggingInfo`. It covers receiver/window/pasteboard/sequence expiry, source
operation masks, once-only completion, exact ancestor handoff, original terminal
cancellation and truthful refusal.

The session component compiles the production Swift URL decoder, geometry,
preview and commit owner, with unrelated sidebar/layout collaborators supplied
by the fixture. It covers public-URL precedence, one-item admission, internal/file
refusal, changed pasteboards, ownership cancellation, same-router external
reservation through native/local receivers, original geometry restoration and
once-only commit/failure.

The production overlay attaches the router to `WebContentsViewCocoa` before
renderer drag delivery. `ExternalSplitDropHost` owns the admitted gesture and
`BrowserWindowController` supplies its original-pane transaction. See
[split groups](../../docs/split-groups.md#external-url-drops-into-ordinary-split-panes).
Changes to the native integration also require the normal actual-target compiler
check for the complete translation unit against the pinned source overlay.
