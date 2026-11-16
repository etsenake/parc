#pragma once
#include <memory>
#include <vector>

#include "base/callback_list.h"
#include "base/functional/callback_forward.h"
#include "components/content_settings/core/common/content_settings_types.h"
#include "components/permissions/permission_prompt.h"
namespace content {
class WebContents;
}
namespace parc {
std::unique_ptr<permissions::PermissionPrompt> CreateSitePermissionPrompt(
    content::WebContents* contents,
    permissions::PermissionPrompt::Delegate* delegate);
void InstallNativeSitePermissions(content::WebContents& contents);
void SetNativeSitePermissionsAttached(content::WebContents& contents,
                                      bool attached);
std::unique_ptr<permissions::PermissionPrompt> CreateNativeSitePermissionPrompt(
    content::WebContents& contents,
    permissions::PermissionPrompt::Delegate* delegate,
    base::RepeatingClosure* on_page_detach = nullptr);
bool IsSystemPermissionOff(ContentSettingsType type);
std::vector<ContentSettingsType> SystemDeniedPermissions();
void OpenSystemPermissionSettings(content::WebContents& contents,
                                  ContentSettingsType type);
base::CallbackListSubscription ObserveSystemPermissions(
    base::RepeatingClosure changed);
}
