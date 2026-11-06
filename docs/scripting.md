# Local scripting


## Objects and commands

The application exposes original normal and incognito browser windows in front-to-back order, including Chromium-created windows after their original page has been adopted and normal link-routing destinations. Each window exposes its accessible tabs and profile-bound Spaces, the actual focused tab (including a focused split child), active Space, identity, title and native window state. A tab exposes its identity, title, URL, loading state and sidebar location (`topApp`, `pinned`, or `unpinned`). A Space exposes its identity, title and tabs, including its profile's Favorites. Unloaded tabs return their saved model metadata; a live page supplies its actual URL, title and loading state only when its original native owner and profile match.

A window or Space can make a tab with an absolute `URL` property. A tab supports `select`, `go back`, `go forward`, `reload`, `stop`, `close`, `execute javascript` and URL assignment. A Space supports `focus`. The application can make a normal or incognito window, and windows support `close`. Window state and sidebar location are read-only. Creation accepts no replacement or arbitrary collection mutation. Private, mixed-context, popup and auxiliary windows are not represented as normal browser windows. A native reservation without an adopted live Browser is unavailable. Requests for an unsupported window mode fail before creation.

For example, these commands use the bundled dictionary (the examples do not run automatically):

```applescript
tell application "Parc"
    set browserWindow to window 1
    tell browserWindow
        set newPage to make new tab with properties {URL:"https://example.com/"}
        select newPage
    end tell
    get URL of active tab of browserWindow
end tell
```

Page navigation commands require the exact tab's existing native page; they do not materialize a replacement for an unloaded or local document tab. Select the tab first to use those page commands. Relative strings are not interpreted as search requests. `javascript:` URL assignment cannot bypass the separate JavaScript-from-Apple-Events permission contract, and local `parc:` document conversion is not exposed by URL assignment.

## Ownership and lifecycle

`BrowserScripting.swift` contains weak locators, not page owners. Every command resolves the original physical window UUID and tab/Space UUID plus profile UUID again. Specifiers use stable unique IDs and retain the original window container. A tab that moved to another owner, changed profile, retired or disappeared cannot retarget a saved locator to another page. No scripting command falls back to the front window or responder chain.

The AppDelegate supplies the application collection and normal-window factory. Native-created normal BrowserWindowControllers join the same collection through their existing ready/adoption path; scripting does not recreate or show them. The copied native reservation records the actual Profile’s off-the-record bit. Each access also classifies the binding’s current live Browser/Profile objects as regular, off-the-record, mixed or unavailable. A shared directory path is never evidence of regular context. An app-owned window showing no page or an Easel can have no native Browser, while an empty native reservation cannot. Existing private or mixed native state invalidates a normal wrapper, including its mode read. Cocoa forwards its scripting getter and `newScriptingObject` to that delegate; its insertion path subsequently writes the collection. Factories commit the real object before returning its wrapper. The setter acknowledges only that issued one-use result. It accepts the post-factory getter shape, which can already contain the object's ordinary locator, without duplicating the object. It rejects replacement, reordering and replay of the issued result. Window insertion checks the retained owner identity even while its first native page is still opening.

BrowserWindowController dispatches navigation through the exact live `PCBrowserView` and validates native page, profile path, observer and owner binding. Selecting a split child uses the existing original-tab selection path; it does not assume the first pane is focused. Closing a tab uses the shared BrowserStore retirement transaction with a singleton requested ID, including the original page's child Peek retirement. The requested child does not become an implicit request to close its entire split group. Saved-tab closing retains its destination, while Today-tab closing follows the existing archive transaction.

Close commands suspend before dispatch, allowing both synchronous local completion and asynchronous native beforeunload approval. They resume on the actual approved or refused result. Window close follows the original native window-close path. Transfer recovery, active transfers, modal/sheet state, retirement, onboarding/replay and shutdown gates reject work rather than leaving a suspended command without an owner. A refusal reports cancellation and keeps the original page/window.

## JavaScript permission and replies

View → Developer → **Allow JavaScript from Apple Events** controls the original selected page's actual Chromium profile preference, `browser.allow_javascript_apple_events` (initially false). Its checkmark reads that preference. The menu retains the original page while tracking and disables stale, unavailable, modal/security-reserved or policy-blocked targets. It uses Chromium's existing toggle: the current CGEvent must have sender PID zero or this process and `kCGEventSourceStateID == kCGEventSourceStateHIDSystemState`. There is no scripting setter for the permission and no parallel UserDefaults authorization. The original profile owns persistence; managed preferences and Developer Tools policy remain authoritative.

`execute tab javascript "…"` suspends its Cocoa command before dispatch and retains the returned native request lease. Native code resolves that exact existing WebContents and primary document, executes through `RenderFrameHost::ExecuteJavaScriptInIsolatedWorld` with `ISOLATED_WORLD_ID_APPLESCRIPT`, then serializes the renderer's value as JSON text with depth limit 200. A JavaScript string therefore returns text containing JSON quotes; objects and arrays return JSON text rather than Apple Event records. The engine's empty/undefined value is represented by its normal JSON null conversion; this interface does not claim JavaScript exception or Promise-await semantics absent from the renderer API.

The request checks the same browser, native page observer, profile, window and weak document before dispatch and reply. Navigation to a new document, page/window/profile destruction, renderer loss, ownership transfer or retirement, revoked permission and policy changes cancel the reply. A scoped native unfreezing lease keeps the original primary frame tree runnable while awaiting its result. It counts overlapping requests, preserves the latest requested freeze state, and never suppresses back/forward-cache freezing. Newly created frames in the same original document receive the same protection. Completion/cancellation releases the leases, with weak cleanup after renderer destruction. A queued completion leaves native observer/destruction stacks before Cocoa resumes. Swift also revalidates its original model/window/profile locator and resumes exactly once. This does not recreate or refocus a page. Background loaded tabs retain their own document; unloaded/local tabs report an unavailable live-page error.

Parc uses a 30-second reply deadline and a 100-millisecond ownership check alongside actual document/profile/window observers. These are explicit adaptations for bounded completion through the independent owner lifecycle. They cancel the outstanding reply; they do not terminate JavaScript already running or reverse side effects. Permission refusal reports `-1743`, cancellation `-128`, timeout `-1712` and a lost model owner `-1728`. macOS Apple Events authorization remains outside this preference; Parc does not grant or bypass system authorization.

## Reference basis










## Incognito ownership and creation

File → **New Incognito Window** (⌘⇧N) and scripting `make new window with properties {incognito:true}` create a genuine Chromium primary off-the-record Browser. `mode:"incognito"` is also accepted at creation; conflicting properties are rejected. The native owner records the exact private Profile separately from its normal parent's path. A copied path never selects privacy. Page creation, classified navigation and the empty window's omnibox use that actual private binding; they cannot fall back to normal browsing. Chromium-created private windows and their DevTools retain the original request's typed private context.


The native parent Profile may not yet be loaded when the front window shows no page (no tab, or a blank tab). Private creation prepares that exact parent asynchronously without making a temporary page. `ParcCreateCommand` suspends private-window creation and returns the actual new wrapper after the native Browser exists; ordinary window/tab creation retains Cocoa's one-use insertion acknowledgment. App shutdown cancels pending creations once, and later readiness cannot create a replacement window. Profile removal, policy or readiness failure returns an error without a simulated owner.




