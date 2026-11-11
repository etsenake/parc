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

class BrowserWindowInterface;
class ChromeBrowserMainParts;
class LoginHandler;
class PrefRegistrySimple;
class PrefService;
class Profile;
class SadTab;
class StartupData;

namespace base {
class CommandLine;
class FilePath;
}

namespace extensions {
class ComponentLoader;
class Extension;
}

namespace gcm {
class GCMClient;
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
class DialogModel;
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

}  // namespace parc_hooks

#endif  // PARC_CHROMIUM_HOOKS_H_
