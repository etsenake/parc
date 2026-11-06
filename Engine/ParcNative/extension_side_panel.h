// Copyright 2026 Parc contributors.
#ifndef PARC_NATIVE_EXTENSION_SIDE_PANEL_H_
#define PARC_NATIVE_EXTENSION_SIDE_PANEL_H_

#import <AppKit/AppKit.h>
#include <memory>
#include "base/functional/callback.h"
#include "chrome/browser/ui/side_panel/side_panel_ui.h"

class BrowserWindowInterface;
namespace content {
class WebContents;
}
namespace input {
struct NativeWebKeyboardEvent;
}

namespace parc {
// App-owned layout boundary. The service owns the actual extension page;
// this host owns its container and supplies the exact Browser's NSWindow.
// The host must outlive the service. Pre-attachment queries return nil/false.
class NativeSidePanelHost {
 public:
  virtual ~NativeSidePanelHost() = default;
  virtual NSWindow* SidePanelWindow() const = 0;
  virtual NSView* SidePanelContainer() const = 0;
  // Includes only this panel's native chrome and content, never the app root.
  virtual NSView* SidePanelFocusScope() const { return SidePanelContainer(); }
  virtual bool IsSidePanelBrowserSelected() const = 0;
  // Called before loading with visible=false, then with visible=true only
  // when the real host is loaded. Return true only if the requested state is
  // applied to the supplied container in this exact window. The service also
  // independently validates native attachment, bounds and visibility.
  virtual bool SetSidePanelVisible(bool visible) = 0;
  virtual bool HandleSidePanelKey(
      content::WebContents* contents,
      const input::NativeWebKeyboardEvent& event) = 0;
};

// Register after Browser features/registry exist, before exposing API calls.
// Uses real window/tab registries and ExtensionSidePanelManager/coordinators.
// Close/Shutdown before detaching the shell or destroying Browser/Profile.
class NativeExtensionSidePanel final : public SidePanelUI {
 public:
  NativeExtensionSidePanel(BrowserWindowInterface& browser,
                           NativeSidePanelHost& host);
  ~NativeExtensionSidePanel() override;
  NativeExtensionSidePanel(const NativeExtensionSidePanel&) = delete;
  NativeExtensionSidePanel& operator=(const NativeExtensionSidePanel&) = delete;

  // Required after selection, container/window association or layout changes.
  // Losing exact ownership cancels pending/visible presentation.
  void HostStateChanged();
  // Completion follows release of all deferred native host leases. Caller
  // must keep Browser/Profile and this host alive through completion and any
  // originating engine callback stack. Valid with an empty TabList. Repeated
  // calls add completion observers; completion is always asynchronous,
  // including the zero-host case, and follows global manager/coordinator
  // destruction. No forced engine deletion inside OnLoaded/Close.
  void Shutdown(base::OnceClosure completion);

  using SidePanelUI::Close;
  using SidePanelUI::Show;
  void Show(SidePanelEntryId,
            std::optional<SidePanelOpenTrigger>,
            bool) override;
  void Show(SidePanelEntryKey,
            std::optional<SidePanelOpenTrigger>,
            bool) override;
  void ShowFrom(SidePanelEntryKey, gfx::Rect) override;
  void Close(SidePanelEntryHideReason, bool) override;
  void Toggle(SidePanelEntryKey, SidePanelOpenTrigger) override;
  std::optional<SidePanelEntryId> GetCurrentEntryId() const override;
  int GetCurrentEntryDefaultContentWidth() const override;
  bool IsSidePanelShowing() const override;
  bool IsSidePanelEntryShowing(const SidePanelEntryKey&) const override;
  bool IsSidePanelEntryShowing(const SidePanelEntryKey&,
                               bool for_tab) const override;
  bool UsesNativeExtensionContent() const override;
  bool IsSidePanelEntryPending(const SidePanelEntryKey&,
                               bool for_tab) const override;
  base::CallbackListSubscription RegisterSidePanelShown(ShownCallback) override;
  void OnActiveTabChanged(content::WebContents*,
                          content::WebContents*,
                          bool) override;
  content::WebContents* GetWebContentsForTest(SidePanelEntryId) override;
  void DisableAnimationsForTesting() override;
  void SetNoDelaysForTesting(bool) override;

 private:
  class State;
  std::shared_ptr<State> state_;
};
}  // namespace parc
#endif
