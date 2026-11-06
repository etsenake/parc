// Copyright 2026 Parc contributors.
// Genuine Chromium IBAN controls in the requesting native page's window.
#pragma once

#include <memory>

#include "base/memory/weak_ptr.h"
#include "chrome/browser/ui/autofill/autofill_bubble_base.h"
#include "content/public/browser/web_contents_observer.h"
#include "ui/gfx/native_ui_types.h"
#include "ui/views/widget/widget_observer.h"

class BrowserWindowInterface;
namespace autofill {
class IbanBubbleControllerImpl;
enum class PaymentsUiClosedReason;
}  // namespace autofill

namespace parc {
// Borrowed by the real controller, self-owned through deferred destruction.
// Host invalidation must precede page reparenting or browser/profile teardown.
class NativeIbanSession final : public autofill::AutofillBubbleBase,
                                public content::WebContentsObserver,
                                public views::WidgetObserver {
 public:
  static bool Supports(const autofill::IbanBubbleControllerImpl&);
  static NativeIbanSession* Create(BrowserWindowInterface&,
                                   content::WebContents&,
                                   gfx::NativeView page_host,
                                   gfx::NativeWindow,
                                   autofill::IbanBubbleControllerImpl&);
  void Hide() override;
  bool IsMouseHovered() const override;
  bool IsPresented() const override;
  void SetPresentationCallback(base::OnceCallback<void(bool)>) override;
  base::WeakPtr<NativeIbanSession> GetWeakPtr();

 private:
  class Controller;
  struct Impl;
  NativeIbanSession(BrowserWindowInterface&,
                    content::WebContents&,
                    gfx::NativeView,
                    gfx::NativeWindow,
                    autofill::IbanBubbleControllerImpl&);
  ~NativeIbanSession() override;
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
  base::WeakPtrFactory<NativeIbanSession> weak_factory_{this};
};
}  // namespace parc
