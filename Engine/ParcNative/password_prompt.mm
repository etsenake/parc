#include "password_prompt.h"

#include <map>
#include <memory>
#include <utility>

#include "base/check.h"
#include "base/functional/bind.h"
#include "base/location.h"
#include "base/memory/weak_ptr.h"
#include "base/no_destructor.h"
#include "base/strings/sys_string_conversions.h"
#include "base/task/single_thread_task_runner.h"
#import "autofill_save_presenter.h"
#include "native_browser.h"
#include "chrome/browser/profiles/profile.h"
#include "chrome/browser/ui/browser_window/public/browser_window_interface.h"
#include "chrome/browser/ui/passwords/bubble_controllers/save_update_bubble_controller.h"
#include "chrome/browser/ui/passwords/manage_passwords_ui_controller.h"
#include "chrome/browser/ui/passwords/passwords_model_delegate.h"
#include "components/password_manager/core/browser/password_form.h"
#include "components/tabs/public/tab_interface.h"
#include "content/public/browser/browser_thread.h"
#include "content/public/browser/navigation_handle.h"
#include "content/public/browser/web_contents.h"
#include "content/public/browser/web_contents_observer.h"
#include "ui/base/base_window.h"

namespace parc {
namespace {
using State = password_manager::ui::State;
using DisplayReason = PasswordBubbleControllerBase::DisplayReason;

bool IsPending(State state) {
  return state == State::PENDING_PASSWORD_STATE ||
         state == State::PENDING_PASSWORD_UPDATE_STATE;
}

// Upstream has no neutral interruption method. Clear only this bubble's weak
// delegate before close reporting, so detach/replacement cannot add dismissal
// strikes or call OnNoInteraction on a later submission.
class NativeSaveUpdateController final : public SaveUpdateBubbleController {
 public:
  using SaveUpdateBubbleController::SaveUpdateBubbleController;
  void CloseWithoutInteraction() {
    auto delegate = std::exchange(delegate_, nullptr);
    OnBubbleClosing();
    if (delegate) {
      delegate->OnBubbleHidden();
    }
  }
};

class NativePasswordPrompt;
using Requests =
    std::map<content::WebContents*, base::WeakPtr<NativePasswordPrompt>>;
Requests& PendingRequests() {
  static base::NoDestructor<Requests> requests;
  return *requests;
}

// Self-owned until the request finishes. Only weak handles cross an AppKit
// callback. Removal precedes controller callbacks, allowing safe replacement.
class NativePasswordPrompt final : public content::WebContentsObserver {
 public:
  NativePasswordPrompt(content::WebContents& contents,
                       BrowserWindowInterface& browser,
                       base::WeakPtr<PasswordsModelDelegate> delegate,
                       bool user_action)
      : content::WebContentsObserver(&contents),
        contents_identity_(&contents),
        browser_identity_(&browser),
        delegate_(std::move(delegate)),
        pending_(delegate_->GetPendingPassword()),
        state_(delegate_->GetState()),
        reason_(user_action ? DisplayReason::kUserAction
                            : DisplayReason::kAutomatic),
        page_(contents.GetNativeView().GetNativeNSView()),
        window_(browser.GetWindow()->GetNativeWindow().GetNativeNSWindow()) {}

  ~NativePasswordPrompt() override {
    weak_factory_.InvalidateWeakPtrs();
    [presenter_ invalidate];
  }

  base::WeakPtr<NativePasswordPrompt> GetWeakPtr() {
    return weak_factory_.GetWeakPtr();
  }

  bool ContextIsValid() const {
    if (finished_ || !web_contents() || !delegate_ ||
        !IsPending(delegate_->GetState()) || delegate_->GetState() != state_ ||
        delegate_->GetWebContents() != web_contents()) {
      return false;
    }
    auto it = PendingRequests().find(contents_identity_);
    if (it == PendingRequests().end() || it->second.get() != this) {
      return false;
    }
    NSView* page = page_;
    NSWindow* window = window_;
    if (!page || !window || page.window != window ||
        web_contents()->GetNativeView().GetNativeNSView() != page ||
        page.hiddenOrHasHiddenAncestor ||
        web_contents()->GetVisibility() == content::Visibility::HIDDEN) {
      return false;
    }
    auto* tab = tabs::TabInterface::MaybeGetFromContents(web_contents());
    auto* browser = tab ? tab->GetBrowserWindowInterface() : nullptr;
    if (!browser || browser != browser_identity_ || !tab->IsActivated() ||
        web_contents()->GetBrowserContext() != browser->GetProfile() ||
        !browser->GetWindow() ||
        browser->GetWindow()->GetNativeWindow().GetNativeNSWindow() != window) {
      return false;
    }
    // A later submission must never authorize the captured sheet's buttons.
    const auto& current = delegate_->GetPendingPassword();
    return current.url == pending_.url &&
           current.signon_realm == pending_.signon_realm &&
           current.username_value == pending_.username_value &&
           current.password_value == pending_.password_value;
  }

  void Start() {
    if (!ContextIsValid()) {
      Finish(PCAutofillSaveInterrupted);
      return;
    }
    const std::string host = delegate_->GetOrigin().host();
    NSString* title = host.empty()
                          ? @"Save this password?"
                          : [NSString stringWithFormat:@"Save password for %@?",
                                base::SysUTF8ToNSString(host)];
    auto weak = GetWeakPtr();
    presenter_ = [[PCAutofillSavePresenter alloc]
        initWithPageView:page_
                  window:window_
                   title:title
                 message:@"That way, it’ll be auto-filled next time"
               saveLabel:(delegate_->IsSavingBlockedByTrustedVaultError()
                              ? @"Unlock and Save" : @"Save")
            declineLabel:@"No"
         validateContext:^{ return weak && weak->ContextIsValid(); }
              completion:^(PCAutofillSaveOutcome outcome) {
                if (weak) {
                  weak->Finish(outcome);
                }
              }];
    if (state_ == State::PENDING_PASSWORD_STATE) {
      presenter_.neverLabel = @"Never on this site";
    }
    presenter_.onPresented = ^{
      if (weak) {
        weak->DidPresent();
      }
    };
    [presenter_ start];
  }

  void DidPresent() {
    if (!ContextIsValid()) {
      Finish(PCAutofillSaveInterrupted);
      return;
    }
    // The actual controller calls OnBubbleShown in its constructor. Construct
    // only after beginSheet succeeded; failure never records a shown bubble.
    controller_ = std::make_unique<NativeSaveUpdateController>(delegate_, reason_);
  }

  void Finish(PCAutofillSaveOutcome outcome) {
    if (finished_) {
      return;
    }
    const bool valid = ContextIsValid();
    finished_ = true;
    auto it = PendingRequests().find(contents_identity_);
    if (it != PendingRequests().end() && it->second.get() == this) {
      PendingRequests().erase(it);
    }
    // Clear native callbacks and detach the exact sheet before data writes.
    // Controller callbacks may navigate, close, or create a replacement.
    presenter_.onPresented = nil;
    [presenter_ invalidate];
    Observe(nullptr);
    auto controller = std::move(controller_);
    auto delegate = std::exchange(delegate_, nullptr);
    weak_factory_.InvalidateWeakPtrs();
    base::SingleThreadTaskRunner::GetCurrentDefault()->DeleteSoon(FROM_HERE, this);
    if (controller) {
      if (!valid || outcome == PCAutofillSaveInterrupted) {
        controller->CloseWithoutInteraction();
        return;
      }
      if (valid) {
        switch (outcome) {
          case PCAutofillSaveAccepted:
            if (controller->IsSavingBlockedByTrustedVaultError()) {
              controller->OnTrustedVaultUnlockClicked();
            } else {
              controller->OnSaveClicked();
            }
            break;
          case PCAutofillSaveNever:
            if (state_ == State::PENDING_PASSWORD_STATE) {
              controller->OnNeverForThisSiteClicked();
            }
            break;
          case PCAutofillSaveDeclined:
            if (state_ == State::PENDING_PASSWORD_UPDATE_STATE) {
              controller->OnNoThanksClicked();
            } else {
              controller->OnNotNowClicked();
            }
            break;
          case PCAutofillSaveInterrupted:
            break;
        }
      }
      controller->OnBubbleClosing();
    } else if (delegate) {
      // Clear the queue reservation without a fabricated shown acknowledgement
      // or a user rejection when native attachment failed.
      delegate->OnBubbleHidden();
    }
  }

  bool IsHovered() const { return presenter_.mouseHovered; }

  void WebContentsDestroyed() override {
    Observe(nullptr);
    Finish(PCAutofillSaveInterrupted);
  }
  void OnVisibilityChanged(content::Visibility visibility) override {
    if (visibility == content::Visibility::HIDDEN) {
      Finish(PCAutofillSaveInterrupted);
    }
  }
  void DidFinishNavigation(content::NavigationHandle* navigation) override {
    if (navigation->HasCommitted() && navigation->IsInPrimaryMainFrame() &&
        !navigation->IsSameDocument()) {
      Finish(PCAutofillSaveInterrupted);
    }
  }

 private:
  // Identities only; actual ownership is re-resolved from the observed page.
  content::WebContents* const contents_identity_;
  BrowserWindowInterface* const browser_identity_;
  base::WeakPtr<PasswordsModelDelegate> delegate_;
  const password_manager::PasswordForm pending_;
  const State state_;
  const DisplayReason reason_;
  __weak NSView* page_;
  __weak NSWindow* window_;
  PCAutofillSavePresenter* __strong presenter_ = nil;
  std::unique_ptr<NativeSaveUpdateController> controller_;
  bool finished_ = false;
  base::WeakPtrFactory<NativePasswordPrompt> weak_factory_{this};
};
}  // namespace

bool UsesNativePasswordPrompt(content::WebContents* contents) {
  auto* tab = contents ? tabs::TabInterface::MaybeGetFromContents(contents)
                       : nullptr;
  return tab && IsNativeBrowser(tab->GetBrowserWindowInterface());
}

bool ShowNativePasswordPrompt(content::WebContents* contents, bool user_action) {
  DCHECK_CURRENTLY_ON(content::BrowserThread::UI);
  if (!UsesNativePasswordPrompt(contents)) {
    return false;
  }
  auto* model = ManagePasswordsUIController::FromWebContents(contents);
  if (!model || !IsPending(model->GetState())) {
    return false;
  }
  auto delegate = model->GetModelDelegateProxy();
  auto contents_lifetime = contents->GetWeakPtr();
  HideNativePasswordPrompt(contents);
  if (!contents_lifetime || !delegate || !IsPending(delegate->GetState())) {
    return false;
  }
  auto* tab = tabs::TabInterface::MaybeGetFromContents(contents);
  auto* browser = tab ? tab->GetBrowserWindowInterface() : nullptr;
  if (!browser || !browser->GetWindow()) {
    return false;
  }
  auto* request =
      new NativePasswordPrompt(*contents, *browser, delegate, user_action);
  auto weak = request->GetWeakPtr();
  PendingRequests()[contents] = weak;
  base::SingleThreadTaskRunner::GetCurrentDefault()->PostTask(
      FROM_HERE, base::BindOnce(&NativePasswordPrompt::Start, weak));
  return true;
}

void HideNativePasswordPrompt(content::WebContents* contents) {
  DCHECK_CURRENTLY_ON(content::BrowserThread::UI);
  auto it = PendingRequests().find(contents);
  if (it != PendingRequests().end() && it->second) {
    it->second->Finish(PCAutofillSaveInterrupted);
  }
}

bool HasNativePasswordPrompt(content::WebContents* contents) {
  auto it = PendingRequests().find(contents);
  return it != PendingRequests().end() && it->second;
}
bool IsNativePasswordPromptHovered(content::WebContents* contents) {
  auto it = PendingRequests().find(contents);
  return it != PendingRequests().end() && it->second && it->second->IsHovered();
}
}  // namespace parc
