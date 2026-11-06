// Copyright 2026 Parc contributors.
// The reviewed source overlay adds this typed method to the real CEF base.
#include <memory>
#include <utility>

#include "base/functional/callback.h"
#include "cef/libcef/browser/javascript_dialog_runner.h"
#include "url/gurl.h"

void CefJavaScriptDialogRunner::RunBeforeUnload(
    CefBrowserHostBase* browser,
    bool is_reload,
    const std::u16string& message_text,
    DialogClosedCallback callback) {
  // Preserve the upstream runners' existing generic-confirm behavior. Parc's
  // page-bound native runner overrides this method and retains the typed reload
  // distinction instead of guessing from an empty origin or localized text.
  Run(browser, content::JAVASCRIPT_DIALOG_TYPE_CONFIRM, GURL(), message_text,
      std::u16string(), std::move(callback));
}
