# Native external split-drop components

Run `bash scripts/test-external-split-drop.sh` for the actual durable model transaction. The fixture uses a temporary session and forces a real failed atomic replacement; it never opens a browser or personal file.

Run `python3 tests/NativeContentDrop/run_components.py router` or `session` for the native components. `--receipt /absolute/path.json` records the exact checked source hashes and output. Both use hidden disposable AppKit windows and unique pasteboards, with no real drag, navigation or personal pasteboard access.


The complete `WebContentsViewCocoa` translation unit and router also require the normal actual-target compiler check against the pinned source overlay. The reusable component does not replace that check or an engine build.
