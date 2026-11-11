// Copyright 2026 Parc contributors.
#ifndef PARC_PARC_MAIN_DELEGATE_H_
#define PARC_PARC_MAIN_DELEGATE_H_

#include <memory>

#include "base/memory/raw_ptr.h"
#include "chrome/app/chrome_main_delegate.h"
#include "parc/parc_content_clients.h"

namespace content {
class BrowserMainRunner;
}

namespace parc {
class NativeApplication;

// Chrome's main delegate for every Parc process. In the browser process it
// keeps Parc's NSApplication, menus and windows: it runs Chrome's browser
// initialization through its own BrowserMainRunner and returns, so the
// caller runs the one main-thread loop, and it leaves out Chrome's
// application subclass, locale override and pack-extension mode.
class ParcMainDelegate final : public ChromeMainDelegate {
 public:
  // `application` is the browser process's native application, null in
  // children. It outlives this delegate.
  explicit ParcMainDelegate(NativeApplication* application);
  ~ParcMainDelegate() override;

  // After content's Run() has returned 0 in the browser process.
  ParcContentBrowserClient& browser_client();
  // Tears down Chrome's browser state on the main thread once the caller's
  // loop has returned; content's Shutdown() follows.
  void ShutdownBrowser();

 private:
  void PreSandboxStartup() override;
  std::optional<int> PreBrowserMain() override;
  std::optional<int> PostEarlyInitialization(InvokedIn invoked_in) override;
  std::variant<int, content::MainFunctionParams> RunProcess(
      const std::string& process_type,
      content::MainFunctionParams main_function_params) override;
  content::ContentClient* CreateContentClient() override;
  content::ContentBrowserClient* CreateContentBrowserClient() override;
  content::ContentRendererClient* CreateContentRendererClient() override;
  content::ContentUtilityClient* CreateContentUtilityClient() override;
  ui::ResourceBundle::Delegate* GetResourceBundleDelegate() override;

  const raw_ptr<NativeApplication> application_;
  ParcContentClient content_client_;
  std::unique_ptr<ParcContentRendererClient> renderer_client_;
  std::unique_ptr<content::BrowserMainRunner> browser_runner_;
};
}  // namespace parc

#endif  // PARC_PARC_MAIN_DELEGATE_H_
