// Copyright 2026 Parc contributors.
#pragma once
#include <memory>
#include "base/memory/weak_ptr.h"
#include "chrome/browser/ui/autofill/autofill_bubble_base.h"
#include "content/public/browser/web_contents_observer.h"
#include "ui/gfx/native_ui_types.h"
#include "ui/views/widget/widget_observer.h"
class BrowserWindowInterface;
namespace autofill {
enum class PaymentsUiClosedReason;
}
namespace parc {
class NativeTabPaymentSession final : public autofill::AutofillBubbleBase,
                                      public content::WebContentsObserver,
                                      public views::WidgetObserver {
 public:
  enum class Kind { kOmnibox, kChurnedOffer, kChurnedConfirmation, kWallet };
  static bool Supports(content::WebContents&, Kind);
  static NativeTabPaymentSession* Create(BrowserWindowInterface&,
                                         content::WebContents&,
                                         gfx::NativeView,
                                         gfx::NativeWindow,
                                         Kind,
                                         bool user_gesture);
  void Hide() override;
  bool IsMouseHovered() const override;
  bool IsPresented() const override;
  void SetPresentationCallback(base::OnceCallback<void(bool)>) override;
  base::WeakPtr<NativeTabPaymentSession> GetWeakPtr();

 private:
  class Action;
  struct Impl;
  NativeTabPaymentSession(BrowserWindowInterface&,
                          content::WebContents&,
                          gfx::NativeView,
                          gfx::NativeWindow,
                          Kind,
                          bool);
  ~NativeTabPaymentSession() override;
  bool IsCurrent() const;
  bool OwnsVisiblePage() const;
  bool CanAct() const;
  void Start();
  void Finish(autofill::PaymentsUiClosedReason);
  void ReportPresentation(bool);
  void ScheduleDestruction();
  void WebContentsDestroyed() override;
  void PrimaryPageChanged(content::Page&) override;
  void OnVisibilityChanged(content::Visibility) override;
  void OnWidgetVisibilityChanged(views::Widget*, bool) override;
  void OnWidgetDestroying(views::Widget*) override;
  std::unique_ptr<Impl> impl_;
  base::WeakPtrFactory<NativeTabPaymentSession> weak_factory_{this};
};
}  // namespace parc
