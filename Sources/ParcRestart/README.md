# Restart helper

`ParcRestart` is the small C executable that reopens Parc after the current
browser process exits during an import that requires a restart. The
[app delegate](../Parc/AppDelegate.swift) owns the restart decision, its
prompts and its orderly termination sequence. How it fits with the other libraries is in the [app architecture guide](../../docs/app-architecture.md).

## Entry point and app connection

[ApplicationRestart.swift](../Parc/ApplicationRestart.swift) starts the
bundled [main.c](main.c) helper with the browser's PID, the app bundle's
absolute path and, for an isolated profile, an optional absolute
`--parc-profile` path. The helper checks that the PID is its parent, then
registers for that process's exit and standard-input events using `kqueue`.

The two processes use pipes. The helper writes `READY` to standard output
after installing the watches. The app can send `RESTART` to arm the helper
or `CANCEL` to stop it. A closed pipe before arming leaves the app closed.
Once armed and the parent has exited, the helper invokes `/usr/bin/open` with
the supplied bundle and optional profile arguments. The helper uses a bounded
wait for the restart handshake and parent exit.

## Build and dependencies

[package-app.sh](../../scripts/package-app.sh) calls
[build.py](../../scripts/build.py), which compiles the helper with Clang, places
it at `Contents/MacOS/ParcRestart` and signs it with the app.
The helper uses macOS process events and the system launcher. It has no
SwiftPM target or dependency on the Chromium framework.

## Checks and guides

The [restart packaging test](../../tests/Packaging/test_restart.py) builds a
temporary fixture from the C entry point. It checks readiness, cancellation,
parent identity and argument boundaries, and intercepts the final launch to
record its arguments. The [app shell](../Parc/README.md) owns the Swift
termination and restart coordination.

Run from the repository root:

```sh
python3 -m unittest discover -s tests/Packaging -p test_restart.py
```

See [browser import](../../docs/browser-import.md) for the import flow,
[onboarding](../../docs/onboarding.md#access-restart-continuation) for
resuming setup after a restart, and [window lifecycle](../../docs/windows-lifecycle.md)
for shutdown and restoration. Chromium forwarding a second launch to an
already-running browser is covered by
[native relaunch](../../tests/NativeRelaunch/README.md).
