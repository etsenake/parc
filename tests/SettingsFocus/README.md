# Settings focus components

Run `bash tests/SettingsFocus/run.sh` on macOS. The runner compiles the production
`SettingsFocusState`/`SettingsNativeWindow` with inert AppKit controls and never
orders a window, activates an application, posts OS input or loads a browser.
The harness substitutes only window/application availability and nested-sheet
attachment flags. Real AppKit fields, the shared field editor, native key-view
links and native button target/actions remain in use.

Checks cover visual key order and reverse links, passive-label exclusion, field
editor selection bookmarks, disabled button dispatch, stale/hidden/detached
control refusal, inactive/non-key/closed/covered parent refusal, fallback focus,
bookmark retirement and nested-sheet cancellation order. AppKit supplies the
native control roles; an unshown field reports `AXUnknown` in this harness, so
the assertions inspect configured labels and control availability. Follow
[AGENTS.md](../../AGENTS.md) when choosing checks.
