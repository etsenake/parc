// Native presentation only. Chromium owns policy, decisions and persistence.
#pragma once
#include <memory>

#include "base/functional/callback_forward.h"
#include "components/permissions/permission_prompt.h"
namespace content {
class WebContents;
}
namespace parc {
// Parc's permission prompt factory, installed in place of Chrome's Views
// prompts. Auxiliary pages and installed native pages get the typed native
// prompt; any other page gets no prompt, so nothing is granted (Chrome leaves
// the request pending or ignores it).
std::unique_ptr<permissions::PermissionPrompt> CreateSitePermissionPrompt(
    content::WebContents* contents,
    permissions::PermissionPrompt::Delegate* delegate);
// Install before navigation. The page starts detached: a prompt created while
// detached is cancelled, and detaching cancels the live prompt.
void InstallNativeSitePermissions(content::WebContents& contents);
void SetNativeSitePermissionsAttached(content::WebContents& contents,
                                      bool attached);
// The actual PermissionRequestManager owns the returned prompt. The factory
// defers presentation until the manager has installed that exact prompt.
// on_page_detach is weakly bound to only this prompt; call it before native
// detachment.
std::unique_ptr<permissions::PermissionPrompt> CreateNativeSitePermissionPrompt(
    content::WebContents& contents,
    permissions::PermissionPrompt::Delegate* delegate,
    base::RepeatingClosure* on_page_detach = nullptr);
}  // namespace parc
