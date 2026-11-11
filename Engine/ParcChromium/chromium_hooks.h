// Copyright 2026 Parc contributors.
// Setters for Parc's hooks inside Chromium files. Each is declared and defined
// in the Chromium .cc named beside it, which never includes this header, so a
// signature that drifts from it fails at link time.
#ifndef PARC_CHROMIUM_HOOKS_H_
#define PARC_CHROMIUM_HOOKS_H_

#include <memory>

#include "components/permissions/permission_prompt.h"

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

}  // namespace parc_hooks

#endif  // PARC_CHROMIUM_HOOKS_H_
