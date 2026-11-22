# Chromium hooks: browser, pages and windows

Part of the [hooks and patches reference](chromium-hooks.md). Startup hooks are installed in the
`ParcMainDelegate` constructor in `Engine/ParcChromium/parc_main_delegate.mm` unless an entry says
otherwise; that runs before resource initialization and before any profile service exists. Browser
code that answers lives in `Engine/ParcNative/` unless a path says otherwise.

## Browser and startup hooks

- **`SetMacMainPartsFactory`**: Parc starts as its own Mac application. In
  `chrome/browser/chrome_browser_main.cc` Parc's main parts replace `ChromeBrowserMainPartsMac`,
  running the POSIX thread setup without Chrome's Mac step. Overriding the browser client's
  `CreateBrowserMainParts` would lose Chromium's full extra-parts sequence. Answered by
  `CreateMacMainParts` in `parc_main_delegate.mm`.
- **`SetMacMainLoopEndHandler`**: quitting ends through Parc's application, not Chrome's
  AppController. `chrome/browser/browser_process_impl.cc` posts Chrome's handler directly from its
  quit path; Parc installs null.
- **`SetMainStartupPolicy`, `SetBrowserStartupPolicy`**: Parc starts with no crash reporting, no
  installer or first-run preferences, no first-run tabs or import, no default-browser switch, and
  with its exact profile folder. The gates sit inside `chrome/app/chrome_main_delegate.cc` and
  `chrome/browser/chrome_browser_main.cc`; a delegate override would have to copy those whole
  methods. Answered by `UsesNativeStartup` in `parc_main_delegate.mm`.
- **`SetMainResourceBundleFactory`, `SetBrowserResourceBundleFactory`**: menus, strings and product
  names say Parc in every process, and network error pages, security warnings and Chromium's
  web-app offline and proxy pages wear Parc's pages and skin. `chrome_main_delegate.cc` and
  `chrome/browser/chrome_resource_bundle_helper.cc` create the shared resource bundle with a null
  delegate and no embedder input. Answered by `NativeResourceBundle` in `parc_main_delegate.mm`; the
  destructor removes both.
- **`SetRegisterProfilePrefs`**: every profile has Parc's search settings, with sign-in and
  translation offers off by default. `chrome/browser/profiles/pref_service_builder_utils.cc` calls it
  after Chrome's and every keyed service's registrations, so Parc's defaults win; a keyed-service
  factory registers in dependency order and can't be sure to run last. Answered by
  `RegisterNativeProfilePrefs` in `native_profiles.mm`.
- **`SetSessionRestorePolicy`**: Parc's restore setting decides whether session cookies and
  session-only settings survive a restart. The decision is `ProfileImpl`'s private
  `ShouldRestoreOldSessionCookies` in `chrome/browser/profiles/profile_impl.cc`. Answered by
  `RestoreNativeSessionState` in `native_profiles.mm`.
- **`SetGaiaAccountsPolicy`**: with sign-in off, Parc never lists Google accounts from cookies.
  The point is `TriggerListAccounts` in the identity manager's internal
  `components/signin/internal/identity_manager/gaia_cookie_manager_service.cc`. Answered by
  `NativeGaiaAccountsAllowed` in `native_profiles.mm`.
- **`SetAlreadyRunningCommandLineHandler`**: opening Parc again, or a link from another app while
  Parc runs, reaches Parc's own window logic. The process singleton hands the launch straight to
  `chrome/browser/ui/startup/startup_browser_creator.cc`. Installed in
  `ParcBrowserMainExtraParts::PostBrowserStart` in `parc_content_clients.mm`, before Chrome's own
  PostBrowserStart lets launches through, and removed in PostMainMessageLoopRun. Answered by
  `NativeApplication::AlreadyRunningRelaunch` in `native_appkit_application.mm`.
- **`SetInternalExtensionInstaller`**: Parc's internal extension loads as a component extension.
  `chrome/browser/extensions/component_loader.cc` builds its component list itself. Installed in
  the `ParcContentBrowserClient` constructor, which adds Parc's internal extension manifest.
- **`SetWebPushFactory`**: web push uses Parc's push client instead of Google's GCM.
  `GCMClientFactory::BuildInstance` in `components/gcm_driver/gcm_client_factory.cc` has no
  embedder override. Installed in the `ParcContentBrowserClient` constructor; answered by
  `CreateWebPushClient` in `Engine/ParcChromium/web_push.cc`.
- **`SetBrowserAdmission`, `SetBrowserLifetime`, `SetBrowserDelegateChange`**: every window, however
  it opens, is a Parc window, and none outlives its record. In `chrome/browser/ui/browser.cc`,
  admission runs in `Browser::Create` before allocation and can refuse; lifetime runs from the
  start of the constructor to the end of the destructor; the delegate change runs in
  `Browser::SetAsDelegate`. Browser-list observers run after construction and before destruction
  ends. Answered by `PrepareNativeBrowserWindow`, `SkipNativeBrowserAdmission` and `NativeBrowser`
  in `native_browser.mm`.
- **`SetBrowserRegistration`, `SetBrowserDeletionGate`**: a closing window finishes its native work
  before Chromium deletes it. `chrome/browser/ui/browser_manager_service.cc` registers the Browser
  in `AddBrowser` before any collection observer, and `DeleteBrowser` waits while Parc defers;
  keyed-service shutdown requires Parc's ready answer. No observer can delay a deletion. Answered by
  `NativeBrowser`.
- **`SetOTRProfileDestructionDeferral`** and its call-in **`DestroyUnusedOTRProfile`**: a private
  window's profile survives while a native operation such as a tab transfer, or a private window
  still being created, needs it. Same file; Parc calls the call-in from `native_browser.mm` when
  the last operation or creation claim ends, or to end a session that a refused creation or a
  Chromium request left without a window. Answered by `DeferNativeOTRProfileDestruction`; see
  [private navigation lifecycle](private-route-lifecycle.md).
- **`SetNativeProfileRemoval`, `SetNativeProfileDeletion`**: removing a profile in Settings is
  crash-safe and owns its disk cleanup. The hooks sit in `chrome/browser/profiles/profile_manager.cc`
  and `delete_profile_helper.cc`, whose unload, tombstone and destruction-complete steps are private.
  Answered by `native_profile_removal.mm`.
- **`SetSessionTabRestoreOmission`, `SetTabRestoreOmission`, `SetSessionServiceOmission`**: pages
  embedded in Easels keep their real tab identity but never return through session restore or
  reopen-closed-tab. The decisions are inside `components/sessions/content/session_tab_helper.cc`,
  `components/sessions/core/tab_restore_service_helper.cc` and
  `chrome/browser/sessions/session_service_base.cc`; the first two carry `SESSIONS_EXPORT`.
  Answered by `IsSessionOmittedFromRestore` in `native_appkit_page.mm`.

## Page and window hooks

- **`SetNativeBrowserWindowFactory`**: every Browser gets Parc's AppKit window.
  `chrome/browser/ui/views/frame/browser_window_factory.cc` defines Chromium's single static window
  factory; a null result keeps Chrome's. Answered by `NativeBrowser::CreateWindow`.
- **`SetNativeBrowserWindowFeatures`**: a native window gets Parc's color source, focus controller,
  DevTools controller and page delegate. `chrome/browser/ui/browser_window/internal/browser_window_features.cc`
  constructs the Views and WebUI versions itself. Answered by `NativeBrowser` and by
  `CreateAppKitFocusController` and `CreateAppKitDevtoolsController` in `native_appkit_host.mm`.
- **`SetPaneFocusRotation`**: pane-focus keys move between Parc's sidebar, toolbar and page.
  `RotatePaneFocus` in `chrome/browser/ui/focus/browser_focus_controller.cc` looks up a Views widget
  native windows lack. Installed in `PreMainMessageLoopRun`; answered by `RotateAppKitPaneFocus`.
- **`SetNavigatorURLRewriter`, `SetNavigatorContentsCreated`, `SetNavigatorBrowserCreator`**: internal
  addresses open in their canonical form, new pages join Parc before their first load, and popups,
  picture-in-picture and new windows open as Parc windows. All three sit at private points in the
  free `Navigate` function in `chrome/browser/ui/navigator/browser_navigator.cc`; only the URL is
  replaced. Answered by `CanonicalInternalURL` in `native_internal_urls.h`,
  `NativeBrowser::OnWebContentsCreated` and `CreateBrowserWindowFrom`.
- **`SetDevToolsBrowserCreator`**: undocked Developer Tools open in a Parc window.
  `chrome/browser/devtools/devtools_window.cc` creates its Browser directly. Answered by
  `CreateBrowserWindowFrom`.
- **`SetAddTabTransition`**: an address typed into Parc counts as typed for history and suggestions.
  `chrome/browser/ui/browser_tabstrip.cc` fixes the transition inside `AddTabAt`. Answered by
  `NativeAddTabTransition` in `parc_main_delegate.mm`.
- **`SetTabUIUpdateGate`**: a page that starts loading before it reaches its tab strip doesn't
  update loading or favicon interface it isn't part of. The gate is synchronous in
  `BrowserUiController::NotifyTabUIChanged`, ahead of both the tab-strip and tab-helper notifications,
  so 157's immediate favicon update is covered too
  (`chrome/browser/ui/browser_ui_controller/browser_ui_controller.cc`). Answered by
  `NativeTabUIUpdateAllowed` in `parc_main_delegate.mm`.
- **`SetEmptyTabColorProvider`**: a window with no tabs still draws in the right colors.
  `GetColorProvider` in `chrome/browser/ui/tabs/tab_strip_api/tab_strip_model_impl/tab_strip_model_adapter_impl.cc`
  assumes a tab exists. Answered by `NativeEmptyTabColorProvider` in `parc_main_delegate.mm`.
- **`SetNativeDevtoolsPresentation`**: docked Developer Tools sit inside Parc's window, with its scrim
  and teardown. `chrome/browser/devtools/devtools_ui_controller.cc` runs Views layout itself; a
  controller Parc made answers update, scrim and teardown. Answered by `UpdateAppKitDevtools`,
  `SetAppKitDevtoolsScrim` and `TearDownAppKitDevtools` in `native_appkit_host.mm`.
- **`SetNativeDevtoolsFrontend`**: a Developer Tools frontend is prepared before its first navigation,
  and its keys reach Parc's shortcuts. Defined in `devtools_window.cc`; the key handler is also
  called from `devtools_window_views.cc`. Answered by `PrepareNativeDevtoolsContents` and
  `HandleNativeDevtoolsKey` in `native_browser.mm`.
- **`SetDevToolsLinkOpener`**: links from Developer Tools with no inspected page, such as a worker's,
  open as a front tab. `DevToolsWindow::OpenInNewTab` in `devtools_window.cc` calls it only then;
  page tools keep the page's own routing. Answered by `OpenNativeDevtoolsLink` in
  `native_browser.mm`, which navigates in the profile's most recent window or a new one.
- **`SetUnloadControllerLifetime`, `SetUnloadControllerTabEvents`, `SetUnloadControllerCloseGates`,
  `SetUnloadControllerPageGates`**: closing a window or moving tabs runs each page's leave-page check
  once and rolls back cleanly. `chrome/browser/ui/unload_controller.cc` keeps its close state and
  beforeunload runner private. Since Chromium 157 splits closing into `CloseContents()` and a const
  query, the page gate sits in the query after its state check, never before it, because closing can
  already have cleared a page's unload state; Parc's own web-contents delegate overrides
  `CloseContents()` to hold a page before Chromium's mutating close runs. Tab attach, detach and
  renderer-crash events stay hooks inside `TabDetachedImpl` and its siblings, because Parc's
  committed-close check must be queued before Chromium clears the controller's unload state and
  queues its own pending-tab processing, which can close the window. Answered by
  `Engine/ParcNative/unload_transactions.cc`.
- **`SetFrameFocusNotifier`**: keyboard shortcuts follow the frame that has focus.
  `content/browser/web_contents/web_contents_impl.cc` (`CONTENT_EXPORT`) calls it where focus
  changes, so `web_contents_observer.h` gains no method. Installed in the `ParcContentBrowserClient`
  constructor; answered by `NotifyFrameFocus` in `Engine/ParcChromium/frame_focus.cc`.

## Browser and startup patches

- **`chromium-direct-startup`**: the startup hooks, each an early return or an added condition at
  its original point rather than a wrapped block, plus the Mac framework path honoring the
  installed framework, which PathService can't reach for direct callers, a Keychain definition whose
  namespace is mutable in implementation and callers, and the staged content entry. Touches
  `chrome_main_delegate.cc`, `browser_process_impl.cc`, `chrome_browser_main.cc`,
  `chrome_resource_bundle_helper.cc`, `pref_service_builder_utils.cc`, `startup_browser_creator.cc`,
  `chrome_paths_mac.mm`, `content/app/content_main.cc` and the `chrome/common` and
  `components/os_crypt/common` build files.
- **`native-browser-overlay`**: the Browser, manager, window, navigator, tab-strip, DevTools
  creator and DevTools link hooks, the DevTools page-command body and the windows API's native
  window-state check (`windows_api.cc`, where Chromium 157 moved `windows.update`), across 11 files
  in `chrome/browser/ui`, `chrome/browser/devtools` and `chrome/browser/extensions/api/tabs`.
  The gates sit at Chromium's private construction, deletion and navigation points.
- **`native-page-retirement`**: only the unload-controller hooks, in `unload_controller.cc`.
- **`native-embedded-pages`**: the three restore-omission hooks, in the three sessions files, and
  one line in `render_widget_host_view_cocoa.mm` that sizes a page from its own bounds rather than
  its size in the window. An Easel zooms its pages with the canvas's magnification, and Chromium
  otherwise laid the page out at the zoomed size and drew it in a corner of its object. No observer
  or delegate sees that measurement; an unscaled view gets the same size as before.
- **`native-host-direct`**: the profile-removal and deletion hooks, capture-picker revocation and
  capture-indicator fixes and tab previews. Touches 9 files, including `profile_manager.cc`,
  `delete_profile_helper.cc`, `desktop_media_picker.cc`, `media_stream_capture_indicator.cc` and
  `tab_features.cc`.
- **`native-session-cookies-direct`**, **`native-signin-disabled-direct`**,
  **`native-web-push-direct`**: each only its hook, in `profile_impl.cc`,
  `gaia_cookie_manager_service.cc` and `gcm_client_factory.cc`.
- **`internal-extension`**: the installer hook in `component_loader.cc` and the internal
  extension's ID in the component allowlist, `allowlist.cc`, which has no embedder list.
- **`native-atomic-import`**: browser import writes history and web data in one transaction, so an
  interrupted import leaves nothing half written. Touches `history_backend` and `web_database`;
  their transactions are private.
- **`native-reader-direct`**: Reader in a private window keeps its caches in that private profile,
  in `dom_distiller_service_factory.cc`, whose profile selection is fixed there.
- **`native-internal-urls-direct-overlay`**, **`native-license-host`**: address completion and
  bookmark import treat Parc's internal and licence addresses as Parc's. Touches the autocomplete
  client and scheme classifier, their BUILD file, `content/public/common/url_utils.cc` and
  `chrome/common/webui_url_constants.cc`.
- **`native-applescript-lifecycle`**: a page an AppleScript request targets stays runnable, and
  visibility changes arrive in order. The lifecycle manager's state in
  `page_lifecycle_state_manager.{h,cc}` is private.

## Page and window patches

- **`native-host-route-direct-overlay`**: native link transport, because a link's policy query runs
  before Chromium creates its navigation request and no public hook reaches that point; also
  per-local-root renderer identity, player adoption across frames and a longer cache stay for a
  casting page. Touches 17 files: the content navigator, frame host and renderer frame, the frame
  and renderer-preference mojoms, the web-contents delegate and Blink's frame client. The deferred
  open notification is the call-in `content::NotifyNativeDeferredOpenURL` in Parc's
  `parc_native_links.h`, so `web_contents.h` stays stock.
- **`native-window-lookup-direct`**, **`native-views-bubble-guards`**: callers that expect a
  BrowserView, toast anchor or Views frame do nothing harmful in a native window. Touches
  `browser_view.cc`, `save_address_bubble_controller.h`, `chrome/test/BUILD.gn` for the owned
  lookup test, `toast_controller.cc` and two page-info and file-access bubbles.
- **`native-fullscreen-window`**: leaving full screen recovers the window's original frame. The
  controller's pending transition and frame are private to
  `native_widget_ns_window_fullscreen_controller.{h,mm}`.
- **`native-input-diagnostics-direct`**: opt-in input and accessibility probes at responder and
  accessibility branches no observer exposes, in four Cocoa, frame-host and accessibility files.
- **`native-external-split-drop`**: dropping a link onto a page can open it in a split, because the
  content view has no drop callback. Touches `web_contents_view_cocoa.mm` and `ui/base/BUILD.gn`,
  which builds Parc's owned `ui/base/cocoa/content_drop_router`.
- **`color-provider-manager-observer`**: Parc's interface redraws when Chromium resets its color
  providers; Chromium has no observer for that. Touches `color_provider_manager.{h,cc}` and
  `native_theme.cc`.
- **`native-side-panel`**: extension side panels work in Parc's sidebar. There is no deregistration
  observer for a pending entry, no seam for the borrowed host and the load-time mark is private;
  seven side-panel coordinator, manager, entry, registry and interface files.
