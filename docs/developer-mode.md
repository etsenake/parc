# Developer Mode

Developer Mode is an app-owned preference for an exact normalized website host. `DeveloperModePreferences` stores explicit enabled hosts separately from disabled default hosts. `localhost` and `127.0.0.1` are enabled by default. Windows, Spaces and normal/private profiles share that UI preference; web storage, permissions and DevTools policy remain owned by the original native profile. Unknown preference versions are preserved and cannot be overwritten by a toggle.

The actual committed HTTP(S) host comes from the original `WebContents`, rather than a saved tab URL. Each visible browser pane and Peek owns its own toolbar. Its address, theme color and security icon reflect that page. Navigation and visible-security/theme changes refresh the toolbar through the existing native page observer. A native fullscreen page retains its existing fullscreen surface. Hiding the toolbar while it owns text focus returns focus only to the same surviving page.

The View → Developer submenu and Control-D share the same host toggle. Menu requests retain an exact page, document revision and host; dispatch revalidates their window and active-page ownership. The toolbar preserves native text editing and marked text. Editing hands the changed string and selection to the existing command-bar session, whose native autocomplete result retains profile, navigation method, headers and transition. No toolbar URL-template or second navigation path is introduced.

The toolbar uses existing policy-aware copying, site information, extensions, split commands and capture owners. Portrait and portion capture are entry routes to `PageCaptureController`; decoration and outputs remain in that single controller. Console, Network and Inspect use the new typed `PCNativePageTool` cases. Chromium checks the live selected page, registered native window, security reservations and DevTools policy before opening the tools. The small `DevToolsToggleAction` extension schedules a native panel selection across frontend loading and calls the existing `DevToolsAPI.showPanel` dispatch once ready. It does not inject JavaScript into the page or recreate its contents.

New commands participate in the existing shortcut registry, conflict editor, command search and native consumed-key priority mechanism. Inspect Elements uses Command-Option-C, JavaScript Console Command-Option-J, and Toggle Developer Mode Control-D. Network Inspector has no recovered default chord. Recovered `promptAfterConsumedByWebView` defaults use the existing Use Both policy for Developer Tools, View Source, Inspect Elements and Toggle Developer Mode. Existing saved Developer Tools/View Source priority behavior is retained during the additive schema-3 migration; custom chords and explicit priorities are preserved.

## Reference and adaptation



## Repeated tools commands and native lifecycle

Developer Tools opens the Elements panel when no controller exists and requests the actual controller's close when one does. Inspect Elements keeps Chromium's inspect-mode action. Console and Network first open their panel when no loaded frontend exists; with a loaded frontend they query its actual selected main panel. A matching panel requests close; a different panel is shown and focused. The result is not inferred from the last command or a profile preference. Command admission is distinct from asynchronous frontend readiness and close completion.


Current Chromium exposes the real selected tab through a narrow `InspectorFrontendAPI.currentPanel` provider installed by its actual `InspectorView`. This callback registration is a current-engine adaptation; it does not execute code in the inspected webpage. The native reply is bound to the original frontend document, requesting page document, original AppKit window and current selected/native owner. A later native show/close request supersedes earlier replies. Missing or stale replies perform no action. The exact key undocked controller uses its existing native window-close transaction, with no saved tab or replacement frontend.

Docking remains owned by Chromium's `SetIsDocked`, actual DevTools WebContents and resize strategy. The existing native pane retains that view through dock/undock/redock and its modal/auxiliary leases. Docked left/right/bottom rectangles come from `ApplyDevToolsContentsResizingStrategy`; Parc does not add a second native dock-size preference. A pending undocked frontend still owned by the controller closes through its genuine beforeunload path before a separate Browser is created. Close completion continues to belong to the actual controller/Browser. The existing `Show` path selects the inspected native host, attaches the tools, and gives the actual tools WebContents initial focus; panel switches use the same path. The pane restores inspected focus only if the departing tools actually owned it.


