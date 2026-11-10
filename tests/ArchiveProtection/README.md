# Automatic archive runtime fixture

Browser/app launch is currently prohibited by [AGENTS.md](../../AGENTS.md).
The runtime procedures below are retained for a future explicitly authorized
run. Source/model checks do not grant that authorization.

`runtime_fixture.py` is a backend-independent loopback fixture with clean,
editable-form, play/pause/stop media and appearance pages. It can seed a new
throwaway session with known tab ages and two profile-specific archive policies.

The current `PCNativePage.archiveProtectionState` implementation in
`Engine/ParcNative/native_appkit_page.mm` reads real Chromium page live-state,
form edits, audio/capture/PiP/VR activity and MediaSession state. Missing required
state returns Unknown. The facade's public `PCArchiveProtectionState` and live
getter remain in use: both Unknown and Protected prevent automatic archive.
The shell also protects current/split and transferring pages and re-reads live
protection immediately before a native retirement transaction. Archive protection
is not a substitute for before-unload consent.

Run from the repository root with a directory that does not already exist:

```sh
python3 tests/ArchiveProtection/runtime_fixture.py --seed-profile build/archive-check
```

Keep the server running. Launch the current packaged app with that exact profile,
using an absolute profile path and keeping its complete development directory
intact:

```sh
/absolute/development/Parc.app/Contents/MacOS/Parc \
  --parc-profile /absolute/path/to/Parc/build/archive-check --parc-diagnostics
```

For an explicitly disposable profile only, `--use-mock-keychain` may be added;
that run cannot establish normal encrypted persistence. The old
`--parc-test-keychain` adapter flag is obsolete. Do not edit session files while
the app is running or seed an existing profile.

The seeded session contains current, overdue, recent, unread, pinned and favorite
tabs, with Work and Personal profiles using distinct intervals. Use
**View → Check Auto-Archive Now** for count-only preflight output. Check background
edited forms and playing/paused media, then stop/unload media and verify a later
sweep uses the fresh state. Check current/split exclusions and both profile
policies independently. The `/appearance` page exercises default canvas, explicit
site colors and CSS color-scheme changes; it is not an archive-state assertion.

`bash scripts/test.sh` retains the actual BrowserStore elapsed-time/profile policy
checks. These model checks, fixture availability and source wiring do not prove
that the independent renderer reports every exemption correctly. Independent archive runtime, a full real-day wait and all capture/PiP/VR
cases remain explicit acceptance work. Real HTTPS responsiveness is also a
separate check.
