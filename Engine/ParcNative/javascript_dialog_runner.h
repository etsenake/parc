// Native CEF runner for one actual WebContents; no BrowserView/NSWindow proxy.
#pragma once

#include <memory>

#include "base/memory/weak_ptr.h"
#include "cef/libcef/browser/javascript_dialog_runner.h"
#include "content/public/browser/web_contents_observer.h"

namespace parc {

class NativeJavaScriptDialogRunner final : public CefJavaScriptDialogRunner,
                                           public content::WebContentsObserver {
 public:
  explicit NativeJavaScriptDialogRunner(content::WebContents& contents);
  ~NativeJavaScriptDialogRunner() override;

  void Run(CefBrowserHostBase* browser,
           content::JavaScriptDialogType message_type,
           const GURL& origin_url,
           const std::u16string& message_text,
           const std::u16string& default_prompt_text,
           DialogClosedCallback callback) override;
  void Handle(bool accept, const std::u16string* prompt_override) override;
  void Cancel() override;

  // Explicit entry point: the pinned CEF base API erases beforeunload into a
  // generic confirm upstream. The reviewed overlay adds typed base/manager
  // dispatch; do not detect this using message text or an empty origin.
  void RunBeforeUnload(CefBrowserHostBase* browser,
                       bool is_reload,
                       const std::u16string& message_text,
                       DialogClosedCallback callback) override;

  // The platform delegate may retain this weak handle; the manager still owns
  // the runner. Do not store an unchecked pointer across manager destruction.
  base::WeakPtr<NativeJavaScriptDialogRunner> GetWeakPtr();

  // Bracket real page detachment/attachment. Reentrant requests during the
  // transition are rejected, including before the old hierarchy is removed.
  void PageHostWillDetach();
  void PageHostDidAttach();

 private:
  void WebContentsDestroyed() override;
  void PrimaryPageChanged(content::Page& page) override;
  struct Impl;
  std::unique_ptr<Impl> impl_;
  base::WeakPtrFactory<NativeJavaScriptDialogRunner> weak_ptr_factory_{this};
};

}  // namespace parc
