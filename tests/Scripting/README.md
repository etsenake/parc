# Scripting component checks

Run `bash scripts/test-scripting.sh` from the repository. The harness packages its executable with the production dictionary as its main bundle, so Cocoa actually registers the scripting classes and unique-ID container specifiers. It constructs a bare NSApplication with a fake delegate and fake browser owners; it does not run the application event loop or create browser windows.

The checks cover Cocoa application getter/factory/collection-setter delegation, the post-factory insertion shape and one-use acknowledgment before native readiness, tab/Space creation, identity/profile invalidation, same-owner navigation dispatch, URL validation, and synchronous/asynchronous close completion. No Apple Events, `osascript`, browser engine, personal profile or user's clipboard are used. Further automation remains explicitly deferred in [local scripting](../../docs/scripting.md).
