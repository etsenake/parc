// Native presentation only. Chromium owns policy, decisions and persistence.
#pragma once
#include <memory>

#include "base/functional/callback_forward.h"
#include "components/permissions/permission_prompt.h"
namespace content {
class WebContents;
}
namespace parc {
// The actual PermissionRequestManager owns the returned prompt. The factory
// defers presentation until the manager has installed that exact prompt.
// on_page_detach is weakly bound to only this prompt; retain it in the actual
// page platform delegate and call before native detachment.
std::unique_ptr<permissions::PermissionPrompt> CreateNativeSitePermissionPrompt(
    content::WebContents& contents,
    permissions::PermissionPrompt::Delegate* delegate,
    base::RepeatingClosure* on_page_detach = nullptr);
}  // namespace parc
