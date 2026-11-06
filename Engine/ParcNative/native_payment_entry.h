// Copyright 2026 Parc contributors.
#pragma once
#include <memory>
#include "base/functional/callback.h"
#include "base/memory/weak_ptr.h"
#import "native_appkit_bridge.h"
class BrowserWindowInterface;
namespace content {
class WebContents;
}
namespace autofill {
class BubbleControllerBase;
}
namespace parc {
// Browser-owned bridge to actual per-document payment controllers. No payment
// credentials or mutable controller objects cross the application ABI.
class NativePaymentEntry final {
 public:
  NativePaymentEntry(
      BrowserWindowInterface&,
      base::RepeatingCallback<bool(content::WebContents&)> validate,
      base::RepeatingClosure changed);
  ~NativePaymentEntry();
  NSArray<PCNativePaymentAction*>* Snapshot(content::WebContents&);
  bool Execute(PCNativePaymentAction*, content::WebContents&);
  bool FeedbackPresented(PCNativePaymentAction*, content::WebContents&);
  void Changed();
  void BeginShutdown();
  void Shutdown(base::OnceClosure);

 private:
  struct DispatchState;
  class Operation;
  autofill::BubbleControllerBase* Validate(PCNativePaymentAction*,
                                           content::WebContents&) const;
  bool ValidPage(content::WebContents&) const;
  void DeliverChanged();
  BrowserWindowInterface& browser_;
  base::RepeatingCallback<bool(content::WebContents&)> validate_;
  base::RepeatingClosure changed_;
  std::shared_ptr<DispatchState> dispatch_;
  uint64_t generation_ = 1;
  bool stopped_ = false;
  bool change_posted_ = false;
  base::WeakPtrFactory<NativePaymentEntry> weak_factory_{this};
};
}  // namespace parc
