// Copyright 2026 Parc contributors.

#ifndef PARC_CHROMIUM_HOOKS_H_
#define PARC_CHROMIUM_HOOKS_H_

#include <memory>
#include <optional>
#include <string>
#include <vector>

#include "base/functional/callback.h"
#include "chrome/browser/ui/sad_tab_types.h"
#include "chrome/browser/ui/tab_sharing/tab_sharing_infobar_delegate.h"
#include "components/permissions/permission_prompt.h"
#include "content/public/browser/weak_document_ptr.h"
#include "media/base/cdm_factory.h"
#include "media/mojo/mojom/content_decryption_module.mojom-forward.h"
#include "mojo/public/cpp/bindings/pending_remote.h"
#include "net/ssl/client_cert_identity.h"
#include "ui/base/page_transition_types.h"
#include "ui/base/resource/resource_bundle.h"
#include "ui/gfx/native_ui_types.h"
#include "ui/shell_dialogs/select_file_dialog.h"
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
class ExtensionInstallPromptShowParams;
class LoginHandler;
class PrefRegistrySimple;
class PrefService;
class Profile;
class ProfileManager;
class RenderViewContextMenu;
class SadTab;
class SessionID;
class StartupData;
class TabStripModel;
class UnloadController;
struct BrowserWindowCreateParams;
struct BrowserWindowDeleter;

namespace autofill {
class AutofillClient;
class AutofillBubbleBase;
class EditAddressProfileDialogController;
class EditAddressProfileView;
enum class AutofillUiPresentation;
}

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
class ExtensionInstallNativeBinding;
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
struct MediaPlayerId;
}

namespace net {
class SSLCertRequestInfo;
class X509Certificate;
}

namespace tabs {
class TabInterface;
}

namespace ui {
class BaseWindow;
class ColorProvider;
class ColorProviderSource;
class DialogModel;
}

namespace web_app {
class AppBrowserController;
}

namespace parc_hooks {
using FileTypeInfoFactory =
    std::unique_ptr<ui::SelectFileDialog::FileTypeInfo> (*)(
        const std::vector<std::u16string>&);
void SetFileTypeInfoFactory(FileTypeInfoFactory factory);
using EditAddressDialog = std::unique_ptr<autofill::AutofillBubbleBase> (*)(
    content::WebContents*,
    autofill::EditAddressProfileDialogController*,
    autofill::EditAddressProfileView*);
void SetEditAddressDialog(EditAddressDialog factory);


using AutofillUiPresentationSupport =
    bool (*)(const autofill::AutofillClient&,
             autofill::AutofillUiPresentation);
void SetAutofillUiPresentationSupport(AutofillUiPresentationSupport support);

using PermissionPromptFactory =
    std::unique_ptr<permissions::PermissionPrompt> (*)(
        content::WebContents* web_contents,
        permissions::PermissionPrompt::Delegate* delegate);
void SetPermissionPromptFactory(PermissionPromptFactory factory);

void SetInternalExtensionInstaller(void (*installer)(extensions::ComponentLoader*));

using ExtensionInstallCapture =
    std::shared_ptr<extensions::ExtensionInstallNativeBinding> (*)(
        ExtensionInstallPromptShowParams&);
void SetExtensionInstallCapture(ExtensionInstallCapture capture);

void SetWebPushFactory(std::unique_ptr<gcm::GCMClient> (*factory)());

void SetFrameFocusNotifier(void (*notifier)(content::WebContents*));

using ExtensionUninstallHandler =
    void (*)(BrowserWindowInterface* browser,
             const extensions::Extension* extension);
void SetExtensionUninstallHandler(ExtensionUninstallHandler handler);

using FolderUploadConfirmation =
    void (*)(std::unique_ptr<ui::DialogModel> model,
             content::WebContents* web_contents,
             content::RenderFrameHost* frame);
void SetFolderUploadConfirmation(FolderUploadConfirmation confirmation);

#ifdef __OBJC__

using NativePageContextMenu =
    bool (*)(RenderViewContextMenu&,
             NSView*,
             MenuControllerCocoa* __strong*);
void SetNativePageContextMenu(NativePageContextMenu presenter);
#endif

using SadTabFactory = std::unique_ptr<SadTab> (*)(content::WebContents*,
                                                  SadTabKind);
void SetSadTabFactory(SadTabFactory factory);

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

using CertificateViewer = void (*)(content::WebContents* web_contents,
                                   gfx::NativeWindow parent,
                                   net::X509Certificate* cert);
void SetCertificateViewer(CertificateViewer viewer);

using ClientCertificateSelector = base::OnceClosure (*)(
    content::WebContents* contents,
    net::SSLCertRequestInfo* cert_request_info,
    net::ClientCertIdentityList client_certs,
    std::unique_ptr<content::ClientCertificateDelegate> delegate);
void SetClientCertificateSelector(ClientCertificateSelector selector);

void SetPasswordPrompt(bool (*uses)(content::WebContents*),
                       bool (*show)(content::WebContents*, bool user_action),
                       void (*hide)(content::WebContents*),
                       bool (*has)(content::WebContents*),
                       bool (*hovered)(content::WebContents*));

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

using TabSharingProfile =
    Profile* (*)(content::GlobalRenderFrameHostId capturer);
void SetTabSharingProfile(TabSharingProfile profile);

void SetLoginHandlerAuthValidator(bool (*validator)(LoginHandler*));

using AlreadyRunningCommandLineHandler =
    void (*)(const base::CommandLine&, const base::FilePath&, void*);
void SetAlreadyRunningCommandLineHandler(
    AlreadyRunningCommandLineHandler handler, void* context);

using ResourceBundleFactory = ui::ResourceBundle::Delegate* (*)(void*);
void SetMainResourceBundleFactory(ResourceBundleFactory factory, void* context);
void SetBrowserResourceBundleFactory(ResourceBundleFactory factory,
                                     void* context);

void SetMainStartupPolicy(bool (*policy)());
void SetBrowserStartupPolicy(bool (*policy)());

using MacMainPartsFactory =
    std::unique_ptr<ChromeBrowserMainParts> (*)(bool, StartupData*);
void SetMacMainPartsFactory(MacMainPartsFactory factory);

void SetMacMainLoopEndHandler(void (*handler)());

void SetCdmServiceChildFlags(int flags);

using CdmCreatedCallback = base::OnceCallback<void(
    mojo::PendingRemote<media::mojom::ContentDecryptionModule>,
    media::mojom::CdmContextPtr,
    media::CreateCdmStatus)>;
using FairPlayCdmCreator = bool (*)(content::RenderFrameHost&,
                                    const media::CdmConfig&,
                                    CdmCreatedCallback&);
void SetFairPlayCdmCreator(FairPlayCdmCreator creator);

void SetRegisterProfilePrefs(void (*registration)(PrefRegistrySimple*));

void SetSessionRestorePolicy(bool (*policy)());

void SetGaiaAccountsPolicy(bool (*policy)(PrefService*));

void SetBrowserAdmission(bool (*admission)(BrowserWindowCreateParams&),
                         void (*unadmitted)());
void SetBrowserLifetime(void (*created)(Browser&),
                        void (*destroyed)(Browser&));
void SetBrowserDelegateChange(
    void (*changed)(Browser&, content::WebContents&, bool));

void SetBrowserRegistration(void (*registered)(BrowserWindowInterface*));

void SetBrowserDeletionGate(bool (*deferred)(BrowserWindowInterface*),
                            bool (*ready)(const BrowserWindowInterface*));

void SetOTRProfileDestructionDeferral(bool (*deferred)(Profile&));
void DestroyUnusedOTRProfile(Profile& profile);

void SetNavigatorContentsCreated(
    void (*created)(BrowserWindowInterface*, content::WebContents&));

using NavigatorURLRewriter = GURL (*)(const GURL&);
void SetNavigatorURLRewriter(NavigatorURLRewriter rewriter);

using OpenedBrowserCreator =
    BrowserWindowInterface* (*)(BrowserWindowInterface* opener,
                                BrowserWindowCreateParams params);
void SetNavigatorBrowserCreator(OpenedBrowserCreator creator);
void SetDevToolsBrowserCreator(OpenedBrowserCreator creator);

void SetAddTabTransition(ui::PageTransition (*transition)());

void SetTabUIUpdateGate(
    bool (*allowed)(TabStripModel&, tabs::TabInterface&));

void SetEmptyTabColorProvider(const ui::ColorProvider* (*provider)());

void SetAutoPictureInPictureVisibilitySync(
    void (*sync)(content::WebContents*, base::OnceCallback<void(bool)>));

void SetVideoPictureInPictureSessionStarted(
    void (*started)(const content::MediaPlayerId& player));

void SetNativeBrowserWindowFactory(
    std::unique_ptr<BrowserWindow, BrowserWindowDeleter> (*factory)(
        BrowserWindowInterface*));

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

void SetPaneFocusRotation(bool (*rotation)(ui::BaseWindow*, bool));

void SetNativeDevtoolsPresentation(
    std::optional<bool> (*update)(DevtoolsUIController&,
                                  content::WebContents*,
                                  bool update_contents),
    bool (*scrim)(DevtoolsUIController&, content::WebContents*, bool visible),
    void (*tear_down)(DevtoolsUIController&));

void SetNativeDevtoolsFrontend(
    void (*prepare)(content::WebContents* inspected,
                    content::WebContents& tools),
    std::optional<bool> (*key)(content::WebContents* inspected,
                               content::WebContents* tools,
                               const input::NativeWebKeyboardEvent&));

void SetSessionTabRestoreOmission(bool (*omitted)(SessionID));
void SetTabRestoreOmission(bool (*omitted)(SessionID));
void SetSessionServiceOmission(bool (*omitted)(SessionID));

void SetNativeProfileRemoval(
    void (*created)(ProfileManager&,
                    base::RepeatingCallback<bool(const base::FilePath&)>,
                    base::RepeatingCallback<bool(const base::FilePath&)>),
    void (*destroyed)(ProfileManager&),
    bool (*creation_refused)(const ProfileManager&, const base::FilePath&),
    bool (*disk_cleanup_owned)(const ProfileManager&, const base::FilePath&),
    bool (*disk_cleanup_run)(ProfileManager&, const base::FilePath&));

void SetNativeProfileDeletion(
    void (*load)(ProfileManager&,
                 const base::FilePath&,
                 base::OnceCallback<void(Profile*)>),
    bool (*cleanup)(ProfileManager&, const base::FilePath&));

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

}

#endif
