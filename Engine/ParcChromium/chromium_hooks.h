// Copyright 2026 Parc contributors.
// Setters for Parc's hooks inside Chromium files. Each is declared and defined
// in the Chromium .cc named beside it, which never includes this header, so a
// signature that drifts from it fails at link time.
#ifndef PARC_CHROMIUM_HOOKS_H_
#define PARC_CHROMIUM_HOOKS_H_

#include <memory>

#include "components/permissions/permission_prompt.h"
#include "ui/base/resource/resource_bundle.h"

class ChromeBrowserMainParts;
class LoginHandler;
class PrefRegistrySimple;
class PrefService;
class StartupData;

namespace base {
class CommandLine;
class FilePath;
}

namespace content {
class WebContents;
}

namespace parc_hooks {

// chrome/browser/ui/views/permissions/permission_prompt_factory.cc
using PermissionPromptFactory =
    std::unique_ptr<permissions::PermissionPrompt> (*)(
        content::WebContents* web_contents,
        permissions::PermissionPrompt::Delegate* delegate);
void SetPermissionPromptFactory(PermissionPromptFactory factory);

// content/browser/web_contents/web_contents_impl.cc
void SetFrameFocusNotifier(void (*notifier)(content::WebContents*));

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
