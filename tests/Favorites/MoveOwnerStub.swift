import AppKit
// The native control component never instantiates a browser controller. The
// production session's weak owner slot is unused; its actual validation and
// one-shot move behavior are exercised against explicit fixture callbacks.
@MainActor final class BrowserWindowController {}
