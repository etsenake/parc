# Chromium hooks: interface routing and prompts

Part of the [hooks and patches reference](chromium-hooks.md). Every prompt keeps its source page and
window checks, is cancelled on detach and navigation, and completes exactly once. Unless an entry
says otherwise, these hooks are installed in `ParcBrowserMainExtraParts::PreMainMessageLoopRun` in
`Engine/ParcChromium/parc_content_clients.mm`, before any page exists, and the answering code lives
in `Engine/ParcNative/`. Parc presents its own pages natively and gives any other page Chromium's
interface.

## Interface hooks

Most of these points are a free function or a factory compiled into one Chromium interface file,
which an embedder cannot override without replacing that file.

- **`SetPermissionPromptFactory`**: camera, microphone, location and other site permission requests
  appear as Parc's sheet, and Parc may answer "no prompt". The factory in
  `chrome/browser/ui/views/permissions/permission_prompt_factory.cc` runs before any Chrome prompt
  logic. Answered by `CreateSitePermissionPrompt` in `site_permissions.mm`.
- **`SetSystemDeniedPermissions`**: Settings' per-site page warns, with its System Settings link,
  when macOS blocks location, camera or microphone for Parc; upstream reports this only on ChromeOS.
  The point is `SiteSettingsHandler::GetSystemDeniedPermissions` in
  `chrome/browser/ui/webui/settings/site_settings_handler.cc`, a member no embedder can override.
  Answered by `SystemDeniedPermissions` in `site_permissions.mm`, which also reports notifications.
- **`SetSadTabFactory`**: a crashed page shows Parc's crash view. The factory is in
  `chrome/browser/ui/sad_tab_controller.cc`. Answered by `CreateSadTab` in `sad_tab.mm`.
- **`SetCertificateViewer`**: viewing a site's certificate opens Parc's viewer instead of the WebUI
  dialog. The point is in `chrome/browser/ui/webui/certificate_viewer/certificate_viewer_webui.cc`.
  Answered by `ShowServerCertificateViewer` in `certificate_viewer.mm`.
- **`SetClientCertificateSelector`**: a site asking for a client certificate shows Parc's chooser.
  The point is in `chrome/browser/ui/views/ssl_client_certificate_selector.cc`, after Chrome's own
  checks. Answered by `ShowClientCertificateSelector` in `client_certificates.mm`.
- **`SetExternalProtocolPrompt`**: "open this link in another app" requests show Parc's prompt with
  the asking document. The point is in `chrome/browser/ui/views/external_protocol_dialog.cc`.
  Answered by `RunExternalProtocolPrompt` in `external_protocol.mm`.
- **`SetLoginHandlerAuthValidator`**: an HTTP sign-in request is shown only while its page still
  asks; a stale one is cancelled. The browser client's owned coordinator presents it, but
  `chrome/browser/ui/login/login_handler.cc` starts the request with no validation callback.
  Answered by `ValidateNativeLoginHandlerAuth` in `http_auth.mm`.
- **`SetPasswordPrompt`**: offers to save or update a password appear as Parc's page sheet, with its
  show, hide, presence and hover answers. `chrome/browser/ui/passwords/manage_passwords_ui_controller.cc`
  drives the Views bubble from its own state. Answered by `password_prompt.mm`.
- **`SetAutofillUiPresentationSupport`**: Chromium asks whether an autofill offer, such as saving a
  card or address, can be presented, so a refused sheet doesn't collect strikes. The free capability
  query in `components/autofill/core/browser/foundations/autofill_client.cc` keeps
  `autofill_client.h` and `chrome_autofill_client.h` Chromium's own. Answered by
  `SupportsAutofillUiPresentation` in `parc_content_clients.mm`.
- **`SetEditAddressDialog`**: editing a saved address from an autofill offer opens Parc's sheet, with
  its account check, in place of the Views editor. `edit_address_profile_view.cc` creates the dialog
  from a controller only it can see. Installed in `parc_content_clients.mm`; answered by
  `ShowNativeAddressEditor` in `native_address_editor.cc`.
- **`SetExtensionInstallCapture`**: installing an extension asks for consent bound to the asking
  page and window. `chrome/browser/extensions/extension_install_prompt.cc` calls it when the prompt
  is created; show-time hooks see the page only once the prompt is ready
  ([decisions](chromium-seams.md#decisions)). Answered by `NativeExtensionInstallService::CaptureFor`
  in `extension_install.mm`.
- **`SetExtensionUninstallHandler`**: removing an extension from its menu runs Parc's confirmation
  for that window and extension. The command is handled inside
  `chrome/browser/extensions/extension_context_menu_model.cc`. Answered by `BeginExtensionUninstall`
  in `extension_uninstall.mm`.
- **`SetExtensionWindowCreateHandler`**: a Shift-clicked link in a PDF opens in a Peek, or in the
  Peek already showing the PDF ([Peek](peek.md#links-inside-a-peek)). Chromium's PDF viewer asks
  the extensions `windows.create` API for the window, which creates it before any page delegate
  sees the address; Chromium's function class can't be subclassed or wrapped for one caller, and
  window creation doesn't know who asked. The point is `WindowsCreateFunction::Run` in
  `chrome/browser/extensions/api/tabs/windows_api.cc`, after the addresses are validated and
  before any window exists; a taken request answers with no window. Answered by
  `OpenNativePdfLinkInPeek` in `native_link_routing.mm`, which takes only the built-in PDF
  viewer's one-address requests. `pdf_link_contract.py` stops the build, naming what changed, if the
  viewer stops opening Shift-clicked links this way or asks for a window anywhere else.
- **`SetFolderUploadConfirmation`**: choosing a folder to upload asks in Parc's sheet and is
  cancelled if the asking frame navigates or goes away. `chrome/browser/file_select_helper.cc`
  hands over the dialog model and frame. Answered by `ShowFolderUploadConfirmation` in
  `folder_upload.mm`.
- **`SetConstrainedWindowPresenters`**: Chromium's tab-modal and window-modal dialogs, such as
  DevTools' "Allow DevTools to edit files" prompt, the remote-debugging approval and the File
  System Access warnings, attach to the Parc page or window that asked instead of floating loose.
  `components/constrained_window/constrained_window_views.cc` parents them to a Views window Parc
  doesn't have, and its helpers are free functions every caller uses directly. It runs in
  `ShowWebModalDialogViews` and `CreateBrowserModalDialogViews`, and Parc takes only dialogs whose
  host or parent isn't a Views window. Answered by `PresentNativeWebModal` and
  `CreateNativeBrowserModal` in `constrained_dialog.mm`.
- **`SetFileTypeInfoFactory`**: a page's file chooser offers both the combined and the per-type
  filters Parc's dialog shows. `chrome/browser/file_select_helper.cc` builds them from the page's
  accept types before the dialog exists. Installed in `file_dialog.mm`; answered by
  `NativeFileTypesFromAcceptType` in `native_file_types.cc`.
- **`SetNativePageContextMenu`**: right-clicking a page shows Parc's menu, cancelled on navigation,
  detach or window invalidation. It runs in `Show` in
  `chrome/browser/ui/cocoa/renderer_context_menu/render_view_context_menu_mac_cocoa.mm`, before the
  Views widget lookup, and is declared only for Objective-C. Installed by
  `RegisterNativePageContextMenu` from `PreMainMessageLoopRun`; answered by
  `native_page_context_menu.mm`.
- **`SetTabSharingPageInfo`, `SetTabSharingInfoBarFactory`, `SetTabSharingProfile`**: sharing a tab
  shows Parc's sharing bar and page-info link, and the session belongs to the sharing page's profile
  rather than the last one used. The points are in
  `chrome/browser/ui/tab_sharing/tab_sharing_infobar_delegate.cc` and
  `chrome/browser/ui/views/tab_sharing/tab_sharing_ui_views.cc`. Answered by `native_tab_sharing.mm`.

## Interface patches

- **`native-site-permissions-direct`**, **`native-site-settings-direct`**, **`native-sad-tab`**,
  **`native-http-auth`**, **`native-tab-sharing-direct`**: each only its hooks, in the files above.
- **`native-server-certificate-viewer-direct`**: the viewer hook, plus the main `chrome/browser`
  target's build edit adding Parc's build flags and, on Mac, the native picture-in-picture API.
  Parc handles certificate requests on its pages and displays the viewer while
  the page is attached. Unowned pages continue through Chromium’s viewer with
  the original entry point and certificate chain.
- **`extension_context_menu_native`**: the uninstall hook, plus a pin action that skips its optional
  feedback when a native window registers no Views element.
- **`native-extension-window-create`**: only its hook, in `windows_api.cc`, after
  `native-browser-overlay`'s window-state change to the same file. Unhooked, Chromium's path runs
  unchanged.
- **`native-page-context-menu-direct-overlay`**: the menu hook, plus the first-observer member in
  `render_view_context_menu.h` that `chromium-direct-shared` uses.
- **`native-password-prompt-direct`**: the password hook, plus a presentation-unavailable result in
  `manage_passwords_ui_controller.h`.
- **`chromium-direct-shared`**: the frame-focus and DevTools key hooks; FileSelectHelper's per-type
  filters, built by Parc's `native_file_types.cc` through `SetFileTypeInfoFactory` because Parc's
  dialog factory can't rebuild them from the merged list; and the context-menu observer, which must
  run first for command dispatch. The frame-focus notification runs where Chromium changes the
  focused frame. A DOM focus notification can miss that transition. Touches `web_contents_impl.cc`,
  `devtools_window_views.cc`, `file_select_helper.cc`, `render_view_context_menu.cc` and two BUILD
  files.
- **`native-devtools-auxiliary`**: app-modal JavaScript dialogs for auxiliary pages such as Developer
  Tools capture their factory when queued and validate ownership after the queue advances; the public
  view factory runs only when shown and can't do both. Adds a per-dialog decision validator in
  `components/javascript_dialogs/app_modal_dialog_{controller,manager}.{h,cc}`.
- **`native-devtools-direct-overlay`**, **`native-developer-panels`**: the docked-controller hooks,
  and the page commands (Developer Tools, Inspect, Console, Network) in DevToolsWindow, its toggle
  action and the frontend's panel query. They need whether the window is closing or loaded and a
  counter that drops a stale panel reply; a Parc port couldn't tell closing from loading and would run
  beforeunload twice. Touches `devtools_ui_controller.cc`, `devtools_window.h`,
  `devtools_toggle_action.{h,cc}` and two DevTools frontend files.
- **`native-intent-picker-direct-overlay`**: "open in app" keeps its source page through
  asynchronous icon loading, in `intent_picker_tab_helper.cc`
  ([decisions](chromium-seams.md#decisions)).
- **`native-client-certificates`**: refuses a stale choice before Chromium shares it for the host and
  exposes the Views list's first-row setup, in the certificate selector files.
- **`native-external-protocol`**: the hook, plus the picture-in-picture occlusion registry that rides
  with it in `picture_in_picture_occlusion_tracker.{h,cc}`.
- **`native-folder-upload-direct-overlay`**: only a dialog host can run a dialog model's accept
  action, so Parc's sheet attaches an acceptance validator to `bubble_dialog_model_host.{h,cc}`;
  also touches `web_contents_modal_dialog_manager.cc`.
- **`native-constrained-window`**: only its hook, in `constrained_window_views.cc`; when Parc
  declines, Chromium's own path runs unchanged.
- **`native-extension-install`**: binds consent when the prompt is created, before the icon loads, in
  `extension_install_prompt.{h,cc}` and the supervised-user delegate. Chromium supplies the default
  icon and handles a caller-supplied icon through its own prompt code
  ([decisions](chromium-seams.md#decisions)).
- **`native-webauthn`**: passkey and security-key requests on opted-in pages use Parc's window; other
  pages run Chromium's dialogs unchanged, and the recovery window holds a typed lease. Adds a native
  host and presentation validation to the request dialog across 9 WebAuthn view, controller, model
  and BUILD files. Chromium 157 deleted the ambient sign-in bubble, so Parc's ambient credential
  chooser lives in `Engine/ParcNative/webauthn.mm` and uses the controller's public model callbacks.
- **`native-autofill-capabilities-direct`**, **`native-autofill-controllers-direct`**,
  **`native-address-editor`**, **`native-address-account`**: presentation results and request state
  for native offers, and routes for native owners without a Views widget
  ([decisions](chromium-seams.md#decisions)). The capability patch spans 63 autofill and payments
  files. The address editor's native dialog and account validation live in Parc's
  `native_address_editor.cc`, reached by one `SetEditAddressDialog` call in
  `edit_address_profile_view.cc`. `ParcBubblePresentation` gives the controllers one shared call for
  adopting a possibly missing view and registering its presentation result, through a friend line
  in the base controller header; Parc's added member definitions compile from Parc-owned files in
  their original autofill targets, and the generation, close-order and manager safeguards stay at
  their original points. Wallet Direct offers preserve their details link and eligibility. Tab
  visibility follows Chromium's bubble manager, and clearing the prompt timestamp first checks
  whether hiding the view synchronously destroyed the controller.
- **`native-protocol-handler-request`**: exposes a "handle this kind of link" request's handler in
  `register_protocol_handler_permission_request.h`; there is no public alternative.
- **`native-current-tab-picker`**, **`native-delegated-picker`**: the share-this-tab picker reports its
  destruction and hiding, and the macOS system picker keeps only an accepted session. Touches the
  share-this-tab dialog and nine desktop-capture list, controller and WebRTC files. Both are
  upstream candidates.
- **`native-settings-visibility`**: Chromium's Settings page takes its section and row hide list
  from a `parcPageVisibility` load-time value when one is present, before its guest check, and
  turns Parc's `parcHiddenRows` (page elements and selectors for their rows) into a stylesheet and
  a search filter, in `chrome/browser/resources/settings/page_visibility.ts`. `settings_section.ts`
  and `settings_subpage.ts` apply it to their page as they appear, `search_settings.ts` skips those
  rows, `route.ts` sends the page's home to Your saved info while You and Google is hidden,
  `reset_profile_dialog.ts` applies it and unticks the report checkbox, and `security_page.html`
  binds the Enhanced Safe Browsing radio's `hidden` to the Safe Browsing choice, so it shows only
  while it's the current choice and the keyboard skips it otherwise. Chromium builds the list
  once, only for guest profiles, and no embedder input reaches a page element's shadow tree;
  styling or scripting the page from outside would break with every redesign. Parc's
  `parc_settings_page.cc` supplies the values through Settings' own registration, and its
  Settings controller subclass turns the reset report off before Chromium's handler sees it
  ([More Settings](settings.md#more-settings)).
- **`native-file-dialogs-direct-overlay`**: background downloads and print preview get native parent
  windows, and a directory listing releases its delegate before reporting completion, so the
  delegate may go away in that call. Touches `download_file_picker.cc`,
  `chrome_select_file_policy.h`, `pdf_printer_handler.cc`, `net/base/directory_lister.{h,cc}` and the
  download BUILD file.
