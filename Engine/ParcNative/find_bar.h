// Native AppKit FindBar for the real Chromium FindBarController.
#pragma once
#import "find_bar_view.h"

#include <string>
#include "base/memory/raw_ptr.h"
#include "base/memory/raw_ref.h"
#include "base/memory/weak_ptr.h"
#include "chrome/browser/ui/find_bar/find_bar.h"
#include "ui/gfx/range/range.h"

namespace content { class WebContents; }
namespace parc {
// Returned for the controller's exact WebContents. Borrowed objects must belong
// to its actual shell window, including when several profiles share a window.
struct NativeFindBarContext {
  NSView* __weak container = nil;
  PCNativeFocusManager* __weak focus_manager = nil;
  NSString* __strong find_key = nil;
  NSString* __strong page_key = nil;
  CGFloat top_inset = 10;
};
class NativeFindBarHost {
 public:
  virtual ~NativeFindBarHost() = default;
  virtual NativeFindBarContext GetFindBarContext(content::WebContents*) = 0;
  virtual void CloseFindOverlappingBubbles() = 0;
};

// Owned by FindBarController; host must outlive it. No Browser/Profile/renderer
// replacement. Source evidence and deliberate156 adaptations are in the test
//
class NativeFindBar final : public FindBar, public FindBarTesting {
 public:
  explicit NativeFindBar(NativeFindBarHost& host);
  ~NativeFindBar() override;
  NativeFindBar(const NativeFindBar&) = delete;
  NativeFindBar& operator=(const NativeFindBar&) = delete;

  FindBarController* GetFindBarController() const override;
  void SetFindBarController(FindBarController*) override;
  void Show(bool animate, bool focus) override;
  void Hide(bool animate) override;
  void SetFocusAndSelection() override;
  void ClearResults(const find_in_page::FindNotificationDetails&) override;
  void StopAnimation() override;
  void MoveWindowIfNecessary() override;
  void SetFindTextAndSelectedRange(const std::u16string&, const gfx::Range&) override;
  std::u16string_view GetFindText() const override;
  gfx::Range GetSelectedRange() const override;
  void UpdateUIForFindResult(const find_in_page::FindNotificationDetails&,
                            const std::u16string&) override;
  void AudibleAlert() override;
  bool IsFindBarVisible() const override;
  void RestoreSavedFocus() override;
  bool HasGlobalFindPasteboard() const override;
  void UpdateFindBarForChangedWebContents() override;
  bool CanPopulateFromSelectedText() override;
  const FindBarTesting* GetFindBarTesting() const override;
  bool HasFocus() const override;
  void CloseOverlappingBubbles() override;
  views::Widget* GetHostWidget() override;

  bool GetFindBarWindowInfo(gfx::Point*, bool*) const override;
  std::u16string_view GetFindSelectedText() const override;
  std::u16string_view GetMatchCountText() const override;
  int GetContentsWidth() const override;
  size_t GetAudibleAlertCount() const override;

 private:
  bool RefreshContext();
  void OnNativeAction(PCNativeFindAction, NSString*);
  void OnNativeFocus(bool);
  const raw_ref<NativeFindBarHost> host_;
  raw_ptr<FindBarController> controller_ = nullptr;
  PCNativeFindView* __strong view_;
  id<PCNativeFindViewDelegate> __strong delegate_;
  std::u16string text_;
  mutable std::u16string selected_text_;
  mutable std::u16string count_text_;
  size_t audible_alerts_ = 0;
  base::WeakPtrFactory<NativeFindBar> weak_factory_{this};
};
}  // namespace parc
