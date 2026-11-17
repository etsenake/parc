// Copyright 2026 Parc contributors.
#ifndef PARC_NATIVE_EXTENSION_POPUP_H_
#define PARC_NATIVE_EXTENSION_POPUP_H_
#include <cstdint>
#include <memory>
#include <string>
#include <vector>

#include "base/functional/callback.h"
#include "chrome/browser/ui/extensions/extension_popup_types.h"
#import "extension_popup_presenter.h"
#include "ui/gfx/native_ui_types.h"
namespace content {
class WebContents;
}
namespace input {
struct NativeWebKeyboardEvent;
}
namespace extensions {
class ExtensionViewHost;
}

namespace parc {
class NativeExtensionPopup final
    : public std::enable_shared_from_this<NativeExtensionPopup> {
 public:
  struct Callbacks {
    base::RepeatingCallback<PCExtensionPopupAnchor*()> anchor;
    base::RepeatingCallback<bool()> security_ui_visible;
    base::RepeatingCallback<bool(content::WebContents*,
                                 const input::NativeWebKeyboardEvent&)>
        menu_key;
    base::RepeatingCallback<bool(content::WebContents*)> inspect;
    base::RepeatingClosure request_hide;
    base::OnceClosure closed;
  };
  NativeExtensionPopup(std::unique_ptr<extensions::ExtensionViewHost> host,
                       NSWindow* parent,
                       PopupShowAction action,
                       ShowPopupCallback callback,
                       Callbacks callbacks);
  ~NativeExtensionPopup();
  NativeExtensionPopup(const NativeExtensionPopup&) = delete;
  NativeExtensionPopup& operator=(const NativeExtensionPopup&) = delete;
  bool Start();
  void Close();
  void Close(base::OnceClosure completion);
  void SecurityUIChanged();
  bool closing() const;
  extensions::ExtensionViewHost* host() const;
  gfx::NativeView native_view() const;

 private:
  class View;
  class Operation;
  class PaintObserver;
  void BeginClose(bool animate);
  bool MayFadeOut();
  void FinishFade();
  void FinalizeClose();
  void MaybeFinalizeClose();
  void Loaded();
  void Resize(const gfx::Size& size);
  void RequestHide(const char* reason = "unspecified");
  void Trace(const char* phase, const char* reason) const;
  bool MayDismissForParentKey();
  void FinishCallback(extensions::ExtensionHost* result);
  std::unique_ptr<extensions::ExtensionViewHost> host_;
  std::unique_ptr<View> view_;
  std::unique_ptr<PaintObserver> paint_observer_;
  __weak NSWindow* parent_;
  PCExtensionPopupPresenter* __strong presenter_ = nil;
  PopupShowAction action_;
  ShowPopupCallback callback_;
  Callbacks callbacks_;
  uint64_t diagnostic_id_ = 0;
  std::string diagnostic_extension_id_;
  bool diagnostic_deferred_logged_ = false;
  int engine_calls_ = 0;
  bool deferred_close_ = false;
  bool close_task_queued_ = false;
  bool started_ = false;
  bool closing_ = false;
  bool hide_queued_ = false;
  bool shown_ = false;
  bool fading_ = false;
  bool close_complete_ = false;
  std::vector<base::OnceClosure> close_completions_;
};
}
#endif
