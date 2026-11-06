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
class OfferNotificationBubbleControllerImpl;
class FilledCardInformationBubbleControllerImpl;
enum class PaymentsUiClosedReason;
}  // namespace autofill
namespace parc {
// Informational, nonmodal native children: copying card details must leave the
// originating form usable. The actual controller continues to own all actions.
class NativePaymentInformationSession final
    : public autofill::AutofillBubbleBase,
      public content::WebContentsObserver,
      public views::WidgetObserver {
 public:
  static bool Supports(const autofill::OfferNotificationBubbleControllerImpl&);
  static bool Supports(
      const autofill::FilledCardInformationBubbleControllerImpl&);
  static NativePaymentInformationSession* Create(
      BrowserWindowInterface&,
      content::WebContents&,
      gfx::NativeView,
      gfx::NativeWindow,
      autofill::OfferNotificationBubbleControllerImpl&,
      bool user_gesture);
  static NativePaymentInformationSession* Create(
      BrowserWindowInterface&,
      content::WebContents&,
      gfx::NativeView,
      gfx::NativeWindow,
      autofill::FilledCardInformationBubbleControllerImpl&,
      bool user_gesture);
  void Hide() override;
  bool IsMouseHovered() const override;
  bool IsPresented() const override;
  void SetPresentationCallback(base::OnceCallback<void(bool)>) override;
  base::WeakPtr<NativePaymentInformationSession> GetWeakPtr();

 private:
  class OfferController;
  class FilledController;
  class Action;
  struct Impl;
  NativePaymentInformationSession(
      BrowserWindowInterface&,
      content::WebContents&,
      gfx::NativeView,
      gfx::NativeWindow,
      autofill::OfferNotificationBubbleControllerImpl*,
      autofill::FilledCardInformationBubbleControllerImpl*,
      bool user_gesture);
  ~NativePaymentInformationSession() override;
  bool IsCurrent() const;
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
  base::WeakPtrFactory<NativePaymentInformationSession> weak_factory_{this};
};
}  // namespace parc
