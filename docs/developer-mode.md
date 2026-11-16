# Developer Mode

Developer Mode stores an exact normalized website-host preference in
`DeveloperModePreferences`. Enabled hosts and disabled default hosts are
separate; `localhost` and `127.0.0.1` default on. The UI preference is shared,
while web storage, permission and DevTools policy remain with the original
native Profile. Unknown preference versions are preserved and cannot be
rewritten by toggling.

Each visible pane and Peek owns its toolbar. Its address, security icon and tint
come from the actual committed page. A native fullscreen page keeps its own
surface. Hiding a toolbar that owns text focus returns focus only to that same
surviving page. Editing preserves marked text and transfers the changed string
and selection into the existing command-bar/native autocomplete session.

## One switch with the developer tools

Developer Mode and Chromium developer tools form one user-facing switch:

- Site Control Center and Control-D follow the site's toolbar setting. On shows
  the toolbar and opens the page's JavaScript Console; off hides it and closes
  that page's tools.
- Developer Tools (Command-Option-I/F12) follows the page's actual open-tools
  state. On a default-enabled host, opening tools does not hide the toolbar.
- Console, Network and Inspect open their own tools panel and enable the toolbar
  when opening tools. Console is Command-Option-J; Inspect is Command-Option-C.
- Toolbar preference is per site; tools are per page. Turning one tab off does
  not close another tab's tools. Pages without an eligible site preference use
  the tools command alone.

The Site Control Center snapshots native command availability before taking key
status, then closes before switching. Dispatch revalidates exact page, document,
window, host and security ownership. `PCNativePage.hasDeveloperTools` queries the
real controller, including undocked tools and excluding closing controllers.

## Toolbar and input

The strip is 40 points high with a monospaced address, 28-point controls and
40-point-page chrome. Trailing controls yield before the address's 20-point
minimum. Its buttons reuse policy-aware copying, site information, extensions,
split commands and the shared capture controller. A page that blocked a pop-up
or redirect adds the [blocked sign](web-interactions.md#banners-and-blocked-pop-ups)
just left of Extensions. Pointer controls provide
current accessibility names and visible focus; hidden, disabled and non-key
surfaces do not retain hover.

The first address edit selects all on the next main-queue turn. The stripe
pattern uses −45°, 15-point bars/gaps and white at 0.3/0.02 in light/dark. The
first-edit offset feedback uses response 0.3, damping 0.4 and resets after 0.1 s;
Reduce Motion skips the displacement. Shortcut registration preserves custom
chords and saved browser-versus-page priorities during schema migration.

## Repeated tools commands and native lifecycle

Generic Developer Tools toggles the real controller. Console/Network open their
requested panel when no loaded frontend exists; otherwise they ask the actual
frontend which main panel is selected. Matching panel closes tools; another
panel switches and focuses. Inspect retains Chromium's inspect-mode action.

The `InspectorFrontendAPI.currentPanel` provider runs in the real DevTools
frontend, not the inspected webpage. Replies bind original frontend document,
requesting page document, AppKit window and selected owner. Newer show/close
requests supersede older replies; missing/stale replies do nothing.

Chromium owns docking, actual tools WebContents and resize strategy. The pane
retains the view across dock/undock/redock and modal leases; it does not add a
second dock-size preference. An undocked window restores its saved frame and
stays hidden until the tools page attaches, then shows/focuses in the same turn.
Pending frontend close uses genuine beforeunload. Focus returns to inspected
content only if departing tools owned it. Native page/frame ownership remains
valid throughout asynchronous loading and close completion.

## Checks

Toolbar, command-admission and preference checks live in
`tests/DeveloperMode`; native frontend, docking and focus checks live in
`tests/NativeDevTools`. Follow [the working contract](../AGENTS.md) before
running window-based helpers.
