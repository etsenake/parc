# Native application relaunch

The already-running Chromium process forwards a second launch to the required AppKit application client. Returning false from `OnAlreadyRunningAppRelaunch` would create a default-styled Chrome window (`cef/include/cef_browser_process_handler.h:103–119`); this native implementation always consumes the handoff, including during shutdown, and never chooses stock browser presentation.

The Swift shell selects only its own ready BrowserWindowController registry, verifies the exact NSWindow registration and client, restores that window if minimized, and activates it. If there is no ready window, the shell's existing new-window command creates one. Explicit HTTP/HTTPS/file destinations go through the actual `application(_:open:)` handler; `--parc-open` search input uses the existing command-bar parser. Requests before shell readiness wait for the first window; requests during aggregate termination are ignored. The existing process's profile, diagnostic mode and engine settings are not changed by a second process. Broader custom URL schemes are not accepted by this relaunch parser.

Chromium's `base::CommandLine::AppendSwitchNative` inserts switches before positional arguments. Therefore the native entry first binds Parc's valued `--parc-profile value` and `--parc-open value` forms as `--name=value`, respecting the literal `--` separator. Without that step, the singleton message could no longer associate a profile path with its switch. The application accepts both spelling forms on initial launch too. Command objects are copied before Chromium releases them; no raw borrowed command object or borrowed callback target survives the callback. Normalized argument strings and the null-terminated argv array remain owned until after engine shutdown because ContentMainParams borrows their storage.

The engine configures Parc Safe Storage with the Parc account before startup.
The direct Chromium startup preserves existing profile encryption and Keychain identity.

Run `bash tests/NativeRelaunch/run.sh`. It compiles and executes the actual Foundation request parser with 22 assertions: argv0 exclusion, profile-operand isolation, malformed/empty switches, both valued forms, copied URLs/query/fragment, relative file origin, switch terminator, destination order and unsupported positional executable schemes. It does not launch an app or Chromium.

The production application entry normalizes and retains arguments through
engine shutdown. AppDelegate receives relaunch requests, queues them during
startup and sends destinations through the same external-link owner as ordinary
application-open events.
