// Copyright 2026 Parc contributors.
// Setters for Parc's hooks inside Chromium files. Each is declared and defined
// in the Chromium .cc named beside it, which never includes this header, so a
// signature that drifts from it fails at link time.
#ifndef PARC_CHROMIUM_HOOKS_H_
#define PARC_CHROMIUM_HOOKS_H_

#include <memory>
#include <optional>
#include <string>

#include "base/functional/callback.h"
#include "chrome/browser/ui/sad_tab_types.h"
#include "chrome/browser/ui/tab_sharing/tab_sharing_infobar_delegate.h"
#include "components/permissions/permission_prompt.h"
#include "content/public/browser/weak_document_ptr.h"
#include "net/ssl/client_cert_identity.h"
#include "ui/base/page_transition_types.h"
#include "ui/base/resource/resource_bundle.h"
#include "ui/gfx/native_ui_types.h"
#include "url/gurl.h"
#include "url/origin.h"

class Browser;
class BrowserFocusController;
class BrowserUiController;
class BrowserWebContentsDelegate;
class BrowserWindow;
class BrowserWindowInterface;
class ChromeBrowserMainParts;
class DesktopBrowserWindowCapabilities;
class DevtoolsUIController;
class ExclusiveAccessManager;
class LoginHandler;
class PrefRegistrySimple;
class PrefService;
class Profile;
class ProfileManager;
class RenderViewContextMenu;
class SadTab;
class SessionID;
class StartupData;
class UnloadController;
struct BrowserWindowCreateParams;
struct BrowserWindowDeleter;

#ifdef __OBJC__
@class MenuControllerCocoa;
@class NSView;
#endif

namespace base {
class CommandLine;
class FilePath;
}

namespace chrome {
class BrowserCommandController;
}

namespace extensions {
class ComponentLoader;
class Extension;
}

namespace gcm {
class GCMClient;
}

namespace input {
struct NativeWebKeyboardEvent;
}

namespace content {
class ClientCertificateDelegate;
class RenderFrameHost;
class WebContents;
}

namespace net {
class SSLCertRequestInfo;
class X509Certificate;
}

namespace ui {
class BaseWindow;
class ColorProviderSource;
class DialogModel;
}

namespace web_app {
class AppBrowserController;
}

namespace parc_hooks {

// chrome/browser/ui/views/permissions/permission_prompt_factory.cc
using PermissionPromptFactory =
    std::unique_ptr<permissions::PermissionPrompt> (*)(
        content::WebContents* web_contents,
        permissions::PermissionPrompt::Delegate* delegate);
void SetPermissionPromptFactory(PermissionPromptFactory factory);

// chrome/browser/extensions/component_loader.cc
void SetInternalExtensionInstaller(void (*installer)(extensions::ComponentLoader*));

// components/gcm_driver/gcm_client_factory.cc
void SetWebPushFactory(std::unique_ptr<gcm::GCMClient> (*factory)());

// content/browser/web_contents/web_contents_impl.cc
void SetFrameFocusNotifier(void (*notifier)(content::WebContents*));

// chrome/browser/extensions/extension_context_menu_model.cc
using ExtensionUninstallHandler =
    void (*)(BrowserWindowInterface* browser,
             const extensions::Extension* extension);
void SetExtensionUninstallHandler(ExtensionUninstallHandler handler);

// chrome/browser/file_select_helper.cc
using FolderUploadConfirmation =
    void (*)(std::unique_ptr<ui::DialogModel> model,
             content::WebContents* web_contents,
             content::RenderFrameHost* frame);
void SetFolderUploadConfirmation(FolderUploadConfirmation confirmation);

#ifdef __OBJC__
// chrome/browser/ui/cocoa/renderer_context_menu/
// render_view_context_menu_mac_cocoa.mm
using NativePageContextMenu =
    bool (*)(RenderViewContextMenu&,
             NSView*,
             MenuControllerCocoa* __strong*);
void SetNativePageContextMenu(NativePageContextMenu presenter);
#endif

// chrome/browser/ui/sad_tab_controller.cc
using SadTabFactory = std::unique_ptr<SadTab> (*)(content::WebContents*,
                                                  SadTabKind);
void SetSadTabFactory(SadTabFactory factory);

// chrome/browser/ui/views/external_protocol_dialog.cc
using ExternalProtocolPrompt =
    void (*)(const GURL& url,
             content::WebContents* web_contents,
             ui::PageTransition page_transition,
             bool has_user_gesture,
             bool is_in_fenced_frame_tree,
             const std::optional<url::Origin>& initiating_origin,
             content::WeakDocumentPtr initiator_document,
             const std::u16string& program_name);
void SetExternalProtocolPrompt(ExternalProtocolPrompt prompt);

// chrome/browser/ui/webui/certificate_viewer/certificate_viewer_webui.cc
using CertificateViewer = void (*)(content::WebContents* web_contents,
                                   gfx::NativeWindow parent,
                                   net::X509Certificate* cert);
void SetCertificateViewer(CertificateViewer viewer);

// chrome/browser/ui/views/ssl_client_certificate_selector.cc
using ClientCertificateSelector = base::OnceClosure (*)(
    content::WebContents* contents,
    net::SSLCertRequestInfo* cert_request_info,
    net::ClientCertIdentityList client_certs,
    std::unique_ptr<content::ClientCertificateDelegate> delegate);
void SetClientCertificateSelector(ClientCertificateSelector selector);

// chrome/browser/ui/passwords/manage_passwords_ui_controller.cc
void SetPasswordPrompt(bool (*uses)(content::WebContents*),
                       bool (*show)(content::WebContents*, bool user_action),
                       void (*hide)(content::WebContents*),
                       bool (*has)(content::WebContents*),
                       bool (*hovered)(content::WebContents*));

// chrome/browser/ui/tab_sharing/tab_sharing_infobar_delegate.cc
using TabSharingPageInfo = void (*)(content::WebContents* web_contents);
void SetTabSharingPageInfo(TabSharingPageInfo page_info);
using TabSharingInfoBarFactory = std::unique_ptr<infobars::InfoBar> (*)(
    content::WebContents* web_contents,
    std::unique_ptr<TabSharingInfoBarDelegate> delegate,
    content::GlobalRenderFrameHostId shared_tab_id,
    content::GlobalRenderFrameHostId capturer_id,
    const std::u16string& shared_tab_name,
    const std::u16string& capturer_name,
    TabSharingInfoBarDelegate::TabRole role,
    TabSharingInfoBarDelegate::TabShareType capture_type,
    base::WeakPtr<ScreensharingControlsHistogramLogger> uma_logger);
void SetTabSharingInfoBarFactory(TabSharingInfoBarFactory factory);

// chrome/browser/ui/views/tab_sharing/tab_sharing_ui_views.cc
using TabSharingProfile =
    Profile* (*)(content::GlobalRenderFrameHostId capturer);
void SetTabSharingProfile(TabSharingProfile profile);

// chrome/browser/ui/login/login_handler.cc
void SetLoginHandlerAuthValidator(bool (*validator)(LoginHandler*));

// chrome/browser/ui/startup/startup_browser_creator.cc
// Installed handlers consume the launch, including a declined native request.
using AlreadyRunningCommandLineHandler =
    void (*)(const base::CommandLine&, const base::FilePath&, void*);
void SetAlreadyRunningCommandLineHandler(
    AlreadyRunningCommandLineHandler handler, void* context);

// chrome/app/chrome_main_delegate.cc
// chrome/browser/chrome_resource_bundle_helper.cc
using ResourceBundleFactory = ui::ResourceBundle::Delegate* (*)(void*);
void SetMainResourceBundleFactory(ResourceBundleFactory factory, void* context);
void SetBrowserResourceBundleFactory(ResourceBundleFactory factory,
                                     void* context);

// Early startup policy in chrome_main_delegate.cc / chrome_browser_main.cc.
void SetMainStartupPolicy(bool (*policy)());
void SetBrowserStartupPolicy(bool (*policy)());

// chrome/browser/chrome_browser_main.cc, before the normal AddParts sequence.
using MacMainPartsFactory =
    std::unique_ptr<ChromeBrowserMainParts> (*)(bool, StartupData*);
void SetMacMainPartsFactory(MacMainPartsFactory factory);

// chrome/browser/browser_process_impl.cc; null omits Chrome's AppController.
void SetMacMainLoopEndHandler(void (*handler)());

// content/browser/media/service_factory.cc
// The ChildProcessHost flags CdmService processes start with, set before the
// first CDM use. A value other than CHILD_NORMAL must be resolved by
// ContentBrowserClient::GetChildProcessPath().
void SetCdmServiceChildFlags(int flags);

// chrome/browser/profiles/pref_service_builder_utils.cc; after all defaults.
void SetRegisterProfilePrefs(void (*registration)(PrefRegistrySimple*));

// chrome/browser/profiles/profile_impl.cc; cookies and session settings.
void SetSessionRestorePolicy(bool (*policy)());

// components/signin/internal/identity_manager/gaia_cookie_manager_service.cc
void SetGaiaAccountsPolicy(bool (*policy)(PrefService*));

// chrome/browser/ui/browser.cc: Browser::Create before any allocation (false
// cancels the creation) and the test-only construction that skips admission,
// the start of the constructor and the end of the destructor, and
// Browser::SetAsDelegate.
void SetBrowserAdmission(bool (*admission)(BrowserWindowCreateParams&),
                         void (*unadmitted)());
void SetBrowserLifetime(void (*created)(Browser&),
                        void (*destroyed)(Browser&));
void SetBrowserDelegateChange(
    void (*changed)(Browser&, content::WebContents&, bool));

// chrome/browser/ui/browser_manager_service.cc, in AddBrowser once ownership
// and subscriptions exist and before any collection observer.
void SetBrowserRegistration(void (*registered)(BrowserWindowInterface*));
// Same file: DeleteBrowser keeps a Browser while `deferred` is true, and
// keyed-service Shutdown requires `ready`.
void SetBrowserDeletionGate(bool (*deferred)(BrowserWindowInterface*),
                            bool (*ready)(const BrowserWindowInterface*));
// Same file: after a primary OTR Profile's last Browser is released,
// DestroyUnusedOTRProfile destroys it when appropriate unless `deferred` keeps
// it for a native operation; Parc calls it again once that operation ends.
void SetOTRProfileDestructionDeferral(bool (*deferred)(Profile&));
void DestroyUnusedOTRProfile(Profile& profile);

// chrome/browser/ui/navigator/browser_navigator.cc, after Navigate creates new
// contents for a Browser and before their first load.
void SetNavigatorContentsCreated(
    void (*created)(BrowserWindowInterface*, content::WebContents&));

// Browsers opened from another one: popups, Picture-in-Picture and new windows
// in chrome/browser/ui/navigator/browser_navigator.cc, and DevTools windows in
// chrome/browser/devtools/devtools_window.cc.
using OpenedBrowserCreator =
    BrowserWindowInterface* (*)(BrowserWindowInterface* opener,
                                BrowserWindowCreateParams params);
void SetNavigatorBrowserCreator(OpenedBrowserCreator creator);
void SetDevToolsBrowserCreator(OpenedBrowserCreator creator);

// chrome/browser/ui/views/frame/browser_window_factory.cc; a null window keeps
// Chrome's.
void SetNativeBrowserWindowFactory(
    std::unique_ptr<BrowserWindow, BrowserWindowDeleter> (*factory)(
        BrowserWindowInterface*));

// chrome/browser/ui/browser_window/internal/browser_window_features.cc
// A non-null color source marks a native shell window, which then gets the
// other three in place of its Views or WebUI ones.
using NativeWebContentsDelegateFactory =
    std::unique_ptr<BrowserWebContentsDelegate> (*)(
        BrowserWindowInterface*,
        ExclusiveAccessManager&,
        chrome::BrowserCommandController&,
        UnloadController&,
        web_app::AppBrowserController*,
        BrowserWindow&,
        DesktopBrowserWindowCapabilities&,
        BrowserUiController&);
void SetNativeBrowserWindowFeatures(
    ui::ColorProviderSource* (*color_provider_source)(BrowserWindowInterface*),
    std::unique_ptr<BrowserFocusController> (*focus_controller)(
        BrowserWindowInterface&),
    std::unique_ptr<DevtoolsUIController> (*devtools_controller)(
        BrowserWindowInterface&),
    NativeWebContentsDelegateFactory web_contents_delegate);

// chrome/browser/ui/focus/browser_focus_controller.cc, before the Views
// Widget lookup. True means the native window rotated focus.
void SetPaneFocusRotation(bool (*rotation)(ui::BaseWindow*, bool));

// chrome/browser/devtools/devtools_ui_controller.cc. A controller Parc made
// answers for itself: `update` returns nullopt to keep Chrome's Views, `scrim`
// returns true once it has handled the call, and `tear_down` runs first in
// DevtoolsUIController::TearDown.
void SetNativeDevtoolsPresentation(
    std::optional<bool> (*update)(DevtoolsUIController&,
                                  content::WebContents*,
                                  bool update_contents),
    bool (*scrim)(DevtoolsUIController&, content::WebContents*, bool visible),
    void (*tear_down)(DevtoolsUIController&));

// chrome/browser/devtools/devtools_window.cc, and devtools_window_views.cc for
// the key handler. `prepare` runs on a DevTools frontend's contents before its
// first navigation. `key` returns nullopt to keep Chromium's routing; a value is
// final, including a rejected skip_if_unhandled event.
void SetNativeDevtoolsFrontend(
    void (*prepare)(content::WebContents* inspected,
                    content::WebContents& tools),
    std::optional<bool> (*key)(content::WebContents* inspected,
                               content::WebContents* tools,
                               const input::NativeWebKeyboardEvent&));

// Easel-owned pages that session and tab restore never record:
// components/sessions/content/session_tab_helper.cc,
// components/sessions/core/tab_restore_service_helper.cc and
// chrome/browser/sessions/session_service_base.cc.
void SetSessionTabRestoreOmission(bool (*omitted)(SessionID));
void SetTabRestoreOmission(bool (*omitted)(SessionID));
void SetSessionServiceOmission(bool (*omitted)(SessionID));

// chrome/browser/profiles/profile_manager.cc. Parc's native Profile removal:
// the manager's lifetime, with whether a path still has a Profile object and
// whether its destruction is pending; the durable-tombstone creation refusal;
// and the disk cleanup that UnloadProfile leaves to it and
// OnProfileDestructionComplete runs.
void SetNativeProfileRemoval(
    void (*created)(ProfileManager&,
                    base::RepeatingCallback<bool(const base::FilePath&)>,
                    base::RepeatingCallback<bool(const base::FilePath&)>),
    void (*destroyed)(ProfileManager&),
    bool (*creation_refused)(const ProfileManager&, const base::FilePath&),
    bool (*disk_cleanup_owned)(const ProfileManager&, const base::FilePath&),
    bool (*disk_cleanup_run)(ProfileManager&, const base::FilePath&));
// chrome/browser/profiles/delete_profile_helper.cc: its scoped cleanup load,
// and the failed-load cleanup a native removal owns.
void SetNativeProfileDeletion(
    void (*load)(ProfileManager&,
                 const base::FilePath&,
                 base::OnceCallback<void(Profile*)>),
    bool (*cleanup)(ProfileManager&, const base::FilePath&));

// chrome/browser/ui/unload_controller.cc. Parc's close and transfer
// transactions: the controller's lifetime, with its private unclosable-app
// policy and beforeunload runner; its tab-strip and renderer events; and the
// gates where those transactions refuse or consume Chromium's close paths.
using UnloadEventsRunner = base::RepeatingCallback<
    bool(content::WebContents*, base::OnceCallback<void(bool)>)>;
void SetUnloadControllerLifetime(
    void (*created)(UnloadController&,
                    BrowserWindowInterface&,
                    base::RepeatingCallback<bool()>,
                    UnloadEventsRunner),
    void (*destroyed)(UnloadController&));
void SetUnloadControllerTabEvents(
    void (*attached)(UnloadController&, content::WebContents*),
    void (*detached)(UnloadController&, content::WebContents*),
    void (*render_process_gone)(UnloadController&, content::WebContents*),
    bool (*absorbs_tab_strip_empty)(UnloadController&));
void SetUnloadControllerCloseGates(
    bool (*blocks_window_close)(const UnloadController&),
    bool (*holds_closing_status)(const UnloadController&),
    bool (*blocks_shutdown)(const UnloadController&));
void SetUnloadControllerPageGates(
    bool (*holds_contents)(const UnloadController&, content::WebContents*),
    std::optional<bool> (*events_result)(const UnloadController&,
                                         content::WebContents*),
    bool (*has_reply)(content::WebContents*),
    bool (*consumes_reply)(UnloadController&, content::WebContents*, bool));

}  // namespace parc_hooks

#endif  // PARC_CHROMIUM_HOOKS_H_
