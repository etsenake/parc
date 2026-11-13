// Copyright 2021 The Chromium Authors

#include "parc/native/native_address_editor.h"

#include <memory>
#include <utility>

#include "base/callback_list.h"
#include "base/functional/bind.h"
#include "base/memory/raw_ptr.h"
#include "base/notreached.h"
#include "chrome/browser/autofill/personal_data_manager_factory.h"
#include "chrome/browser/autofill/ui/ui_util.h"
#include "chrome/browser/ui/autofill/autofill_bubble_base.h"
#include "chrome/browser/ui/autofill/edit_address_profile_dialog_controller.h"
#include "chrome/browser/ui/views/autofill/edit_address_profile_view.h"
#include "components/autofill/core/browser/data_manager/personal_data_manager.h"
#include "components/constrained_window/constrained_window_views.h"
#include "components/signin/public/identity_manager/account_info.h"
#include "components/tabs/public/tab_interface.h"
#include "content/public/browser/navigation_handle.h"
#include "content/public/browser/web_contents.h"
#include "content/public/browser/web_contents_observer.h"
#include "ui/views/widget/widget.h"

namespace parc {
namespace {
using autofill::AutofillBubbleBase;
using autofill::EditAddressProfileView;
class NativeAddressEditor : public AutofillBubbleBase,
                         public content::WebContentsObserver {
 public:
  NativeAddressEditor(std::unique_ptr<views::Widget> dialog,
                   EditAddressProfileView* profile_view,
                   content::WebContents* native_owner);
  NativeAddressEditor(const NativeAddressEditor&) = delete;
  NativeAddressEditor& operator=(const NativeAddressEditor&) = delete;
  ~NativeAddressEditor() override;

 private:
  void Hide() override;
  bool IsMouseHovered() const override;

  void CloseWidget(views::Widget::ClosedReason closed_reason);
  void WebContentsDestroyed() override;
  void DidFinishNavigation(content::NavigationHandle* navigation) override;
  void OnVisibilityChanged(content::Visibility visibility) override;

  base::CallbackListSubscription native_tab_detach_;
  std::unique_ptr<views::Widget> dialog_;
  raw_ptr<EditAddressProfileView> profile_view_ = nullptr;
};

NativeAddressEditor::NativeAddressEditor(std::unique_ptr<views::Widget> dialog,
                                 EditAddressProfileView* profile_view,
                                 content::WebContents* native_owner)
    : content::WebContentsObserver(native_owner),
      dialog_(std::move(dialog)),
      profile_view_(profile_view) {
  dialog_->MakeCloseSynchronous(
      base::BindOnce(&NativeAddressEditor::CloseWidget, base::Unretained(this)));
  if (native_owner) {
    native_tab_detach_ =
        tabs::TabInterface::GetFromContents(native_owner)->RegisterWillDetach(
            base::BindRepeating(
                [](NativeAddressEditor* self, tabs::TabInterface*,
                   tabs::TabInterface::DetachReason) { self->Hide(); },
                base::Unretained(this)));
  }
}

NativeAddressEditor::~NativeAddressEditor() = default;

void NativeAddressEditor::Hide() {
  if (!dialog_) {
    return;
  }
  profile_view_->InvalidateNativeOwner();
  dialog_->Close();
}

bool NativeAddressEditor::IsMouseHovered() const {
  NOTREACHED();
}

void NativeAddressEditor::CloseWidget(views::Widget::ClosedReason closed_reason) {
  auto dialog = std::move(dialog_);
  Observe(nullptr);
  native_tab_detach_ = {};
  profile_view_->WidgetClosed();
  dialog.reset();
}

void NativeAddressEditor::WebContentsDestroyed() {
  Hide();
}

void NativeAddressEditor::DidFinishNavigation(content::NavigationHandle* navigation) {
  if (navigation->IsInPrimaryMainFrame() && navigation->HasCommitted() &&
      !navigation->IsSameDocument()) {
    Hide();
  }
}

void NativeAddressEditor::OnVisibilityChanged(content::Visibility visibility) {
  if (visibility == content::Visibility::HIDDEN) {
    Hide();
  }
}

}
std::unique_ptr<autofill::AutofillBubbleBase> ShowNativeAddressEditor(
    content::WebContents* web_contents,
    autofill::EditAddressProfileDialogController* controller,
    autofill::EditAddressProfileView* dialog) {
  using namespace autofill;

  if (web_contents->GetTopLevelNativeWindow() &&
      !views::Widget::GetWidgetForNativeWindow(
          web_contents->GetTopLevelNativeWindow())) {
    if (controller->GetIsValidatable()) {
      const auto account = GetPrimaryAccountInfoFromBrowserContext(
          web_contents->GetBrowserContext());
      dialog->SetNativeAccountValidator(base::BindRepeating(
          [](base::WeakPtr<content::WebContents> contents,
             CoreAccountId original_account) {
            if (!contents || original_account.empty()) {
              return false;
            }
            auto current = GetPrimaryAccountInfoFromBrowserContext(
                contents->GetBrowserContext());
            auto* pdm = PersonalDataManagerFactory::GetForBrowserContext(
                contents->GetBrowserContext());
            return current && !current->IsEmpty() &&
                   current->GetAccountId() == original_account && pdm &&
                   pdm->address_data_manager()
                       .IsEligibleForAddressAccountStorage();
          },
          web_contents->GetWeakPtr(),
          account ? account->GetAccountId() : CoreAccountId()));
    }
    auto widget = constrained_window::ShowWebModalDialogViewsOwned(
        dialog, web_contents, views::Widget::InitParams::CLIENT_OWNS_WIDGET);
    dialog->RequestFocus();
    return std::make_unique<NativeAddressEditor>(std::move(widget), dialog,
                                            web_contents);
  }
  return nullptr;
}
}
