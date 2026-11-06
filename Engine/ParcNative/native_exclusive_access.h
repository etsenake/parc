// Copyright 2026 Parc contributors.
#ifndef PARC_NATIVE_NATIVE_EXCLUSIVE_ACCESS_H_
#define PARC_NATIVE_NATIVE_EXCLUSIVE_ACCESS_H_
#import <AppKit/AppKit.h>

#include <memory>

#include "chrome/browser/ui/browser_window.h"
#include "chrome/browser/ui/exclusive_access/exclusive_access_bubble.h"
#include "chrome/browser/ui/exclusive_access/exclusive_access_bubble_hide_callback.h"
@class PCNativeHostDecision;
namespace parc {
// Real native warning using the current controller's text and timing contract.
//
class NativeExclusiveAccess final : public ExclusiveAccessBubble {
 public:
  static std::unique_ptr<NativeExclusiveAccess> Replace(
      std::unique_ptr<NativeExclusiveAccess> old,
      NSWindow*,
      const ExclusiveAccessBubbleParams&,
      ExclusiveAccessBubbleHideCallback);
  ~NativeExclusiveAccess() override;
  bool visible() const;

 private:
  NativeExclusiveAccess(NSWindow*,
                        const ExclusiveAccessBubbleParams&,
                        ExclusiveAccessBubbleHideCallback);
  void Show() override;
  void Hide() override;
  void Interrupt();
  class State;
  std::shared_ptr<State> state_;
};
PCNativeHostDecision* ShowNativeDownloadCloseDecision(
    NSWindow*,
    int count,
    DownloadCloseType,
    base::OnceCallback<void(bool)>);
PCNativeHostDecision* ShowNativeCaretDecision(BrowserWindowInterface&,
                                              NSWindow*);
// Actual private Profile command, with explicit consent before closing only
// that Profile's browsers. Never clears or closes the original profile.
// TOOLS16: this is the recovered 430×180 AppKit decision sheet. Ordinary
// profile Clear Browsing Data stays Chromium WebUI; do not invent a second
// native clear-data layout.
PCNativeHostDecision* ShowNativePrivateProfileDecision(
    BrowserWindowInterface&, NSWindow*, bool history_information);
void CancelNativeHostDecision(PCNativeHostDecision*);
}  // namespace parc
#endif
