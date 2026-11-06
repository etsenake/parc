// Page-owned local saves and genuine Chromium account-address presentation.
#pragma once
#include <memory>

#include "base/memory/weak_ptr.h"
#include "chrome/browser/ui/autofill/autofill_bubble_base.h"
#include "components/signin/public/base/signin_buildflags.h"
#include "content/public/browser/web_contents_observer.h"
#include "ui/gfx/native_ui_types.h"
#include "ui/views/widget/widget_observer.h"

class BrowserWindowInterface;
namespace autofill {
class AutofillProfile;
class AddressBubbleBaseView;
class SaveAddressBubbleController;
class SaveCardBubbleControllerImpl;
class UpdateAddressBubbleController;
}  // namespace autofill

namespace parc {
// UI-thread-only. Self-owned until result delivery and deferred destruction;
// never delete through its borrowed bubble pointer. Keep only GetWeakPtr() for
// host invalidation. Call PageHostWillDetach BEFORE any reparent/profile swap.
// Browser/Profile must remain valid until host teardown has interrupted
// requests.
class NativeAutofillSaveSession final : public autofill::AutofillBubbleBase,
                                        public content::WebContentsObserver,
                                        public views::WidgetObserver {
 public:
  // Caller capability checks MUST precede entering Chromium DoShowBubble. These
  // predicates inspect real current controller state; they do not consume it.
  static bool SupportsLocalCard(
      const autofill::SaveCardBubbleControllerImpl& controller);
  static bool SupportsLocalAddress(
      const autofill::SaveAddressBubbleController& controller);

  static bool SupportsAccountAddress(
      const autofill::SaveAddressBubbleController& controller);

  // Preconditions: supports predicate and actual TabInterface/Browser identity.
  // The page_host contains this WebContents' native view in supplied window.
  // A detached/closing association completes as interruption asynchronously;
  // factory never completes inline, even if its native context is unavailable.
  static NativeAutofillSaveSession* CreateLocalCard(
      BrowserWindowInterface& browser,
      content::WebContents& contents,
      gfx::NativeView page_host,
      gfx::NativeWindow window,
      autofill::SaveCardBubbleControllerImpl& controller);
  static NativeAutofillSaveSession* CreateLocalAddress(
      BrowserWindowInterface& browser,
      content::WebContents& contents,
      gfx::NativeView page_host,
      gfx::NativeWindow window,
      std::unique_ptr<autofill::SaveAddressBubbleController> controller);
  // An account update returns null if its real account/storage is unavailable.
  static NativeAutofillSaveSession* CreateAddressUpdate(
      BrowserWindowInterface& browser,
      content::WebContents& contents,
      gfx::NativeView page_host,
      gfx::NativeWindow window,
      std::unique_ptr<autofill::UpdateAddressBubbleController> controller);

  static NativeAutofillSaveSession* CreateAccountAddress(
      BrowserWindowInterface& browser,
      content::WebContents& contents,
      gfx::NativeView page_host,
      gfx::NativeWindow window,
      std::unique_ptr<autofill::SaveAddressBubbleController> controller);
#if BUILDFLAG(ENABLE_DICE_SUPPORT)
  static NativeAutofillSaveSession* CreateAddressSignInPromo(
      BrowserWindowInterface& browser,
      content::WebContents& contents,
      gfx::NativeView page_host,
      gfx::NativeWindow window,
      const autofill::AutofillProfile& profile);
#endif

  void Hide() override;
  bool IsMouseHovered() const override;
  bool IsPresented() const override;
  void SetPresentationCallback(base::OnceCallback<void(bool)>) override;
  void PageHostWillDetach();
  base::WeakPtr<NativeAutofillSaveSession> GetWeakPtr();

 private:
  NativeAutofillSaveSession(BrowserWindowInterface& browser,
                            content::WebContents& contents,
                            gfx::NativeView page_host,
                            gfx::NativeWindow window);
  ~NativeAutofillSaveSession() override;
  bool ContextIsValid() const;
  bool CardIsCurrent() const;
  bool AddressIsCurrent() const;
  void Start();
  void StartAddressUpdate();
  void StartAccountAddress();
#if BUILDFLAG(ENABLE_DICE_SUPPORT)
  void StartAddressSignInPromo();
#endif
  void PresentAddressView(autofill::AddressBubbleBaseView* view);
  void Complete(int outcome);
  void ReportPresentation(bool presented);
  void WebContentsDestroyed() override;
  void OnVisibilityChanged(content::Visibility visibility) override;
  void DidFinishNavigation(content::NavigationHandle* navigation) override;
  void OnWidgetVisibilityChanged(views::Widget* widget, bool visible) override;
  void OnWidgetDestroying(views::Widget* widget) override;
  struct Impl;
  std::unique_ptr<Impl> impl_;
  base::WeakPtrFactory<NativeAutofillSaveSession> weak_factory_{this};
};
}  // namespace parc
