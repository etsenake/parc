#include "javascript_dialog_runner.h"

#include <optional>
#include <utility>

#include "base/functional/callback.h"
#include "base/strings/sys_string_conversions.h"
#include "cef/libcef/browser/browser_host_base.h"
#include "cef/libcef/browser/thread_util.h"
#include "components/javascript_dialogs/app_modal_dialog_manager.h"
#include "components/strings/grit/components_strings.h"
#include "content/public/browser/navigation_controller.h"
#include "content/public/browser/render_frame_host.h"
#include "content/public/browser/web_contents.h"
#include "content/public/browser/web_contents_user_data.h"
#include "ui/base/l10n/l10n_util.h"
#include "url/origin.h"
#import "javascript_dialog_presenter.h"
#include "native_repost_form_warning_api.h"

// The block owns this box, not the runner. A result can synchronously delete
// the runner/manager without leaving a callback into their destroyed storage.
@interface PCJavaScriptDialogCallback : NSObject {
 @public
  CefJavaScriptDialogRunner::DialogClosedCallback callback;
}
- (void)complete:(BOOL)accepted input:(NSString*)input;
@end

@implementation PCJavaScriptDialogCallback
- (void)complete:(BOOL)accepted input:(NSString*)input {
  if (callback) {
    std::move(callback).Run(accepted, base::SysNSStringToUTF16(input));
  }
}
@end

namespace parc {
namespace {
// CEF passes the alerting frame's URL, not its origin. The frame committed at
// that URL supplies its real origin (an about:blank or srcdoc frame inherits
// one); several frames there with different origins fall back to the URL.
url::Origin AlertingOrigin(content::WebContents& contents, const GURL& url) {
  std::optional<url::Origin> found;
  bool ambiguous = false;
  contents.GetPrimaryMainFrame()->ForEachRenderFrameHost(
      [&](content::RenderFrameHost* frame) {
        if (frame->GetLastCommittedURL() != url) {
          return;
        }
        const url::Origin& origin = frame->GetLastCommittedOrigin();
        ambiguous |= found && !found->IsSameOriginWith(origin);
        found = origin;
      });
  return found && !ambiguous ? *found : url::Origin::Create(url);
}
}  // namespace

struct NativeJavaScriptDialogRunner::Impl {
  PCJavaScriptDialogPresenter* __strong presenter;
  //
  //
  // confirm and prompt count before presentation; a set block skips them.
  //
  // Chromium's own suppression does on navigation.
  int displayed = 0;
  bool blocking = false;
};

NativeJavaScriptDialogRunner::NativeJavaScriptDialogRunner(
    content::WebContents& contents)
    : content::WebContentsObserver(&contents), impl_(std::make_unique<Impl>()) {
  CEF_REQUIRE_UIT();
  NSView* page = contents.GetNativeView().GetNativeNSView();
  if (page) {
    impl_->presenter =
        [[PCJavaScriptDialogPresenter alloc] initWithPageView:page];
  }
}

NativeJavaScriptDialogRunner::~NativeJavaScriptDialogRunner() {
  CEF_REQUIRE_UIT();
  weak_ptr_factory_.InvalidateWeakPtrs();
  Observe(nullptr);
  [impl_->presenter invalidate];
}

void NativeJavaScriptDialogRunner::Run(
    CefBrowserHostBase* browser,
    content::JavaScriptDialogType message_type,
    const GURL& origin_url,
    const std::u16string& message_text,
    const std::u16string& default_prompt_text,
    DialogClosedCallback callback) {
  CEF_REQUIRE_UIT();
  if (!web_contents() || !browser ||
      browser->GetWebContents() != web_contents() || !impl_->presenter) {
    std::move(callback).Run(false, std::u16string());
    return;
  }
  PCJavaScriptDialogKind kind;
  switch (message_type) {
    case content::JAVASCRIPT_DIALOG_TYPE_ALERT:
      kind = PCJavaScriptDialogAlert;
      break;
    case content::JAVASCRIPT_DIALOG_TYPE_CONFIRM:
      kind = PCJavaScriptDialogConfirm;
      break;
    case content::JAVASCRIPT_DIALOG_TYPE_PROMPT:
      kind = PCJavaScriptDialogPrompt;
      break;
    default:
      std::move(callback).Run(false, std::u16string());
      return;
  }
  if (impl_->blocking) {
    std::move(callback).Run(false, std::u16string());
    return;
  }
  //
  const bool offer_suppression = ++impl_->displayed > 5;
  PCJavaScriptDialogCallback* completion = [PCJavaScriptDialogCallback new];
  completion->callback = std::move(callback);
  // Chromium's title ("<origin> says", the embedded-page and nonstandard
  //
  content::RenderFrameHost* main = web_contents()->GetPrimaryMainFrame();
  NSString* title = base::SysUTF16ToNSString(
      javascript_dialogs::AppModalDialogManager::GetSiteFrameTitle(
          main->GetLastCommittedURL(), main->GetLastCommittedOrigin(),
          AlertingOrigin(*web_contents(), origin_url)));
  PCJavaScriptDialogPresenter* presenter = impl_->presenter;
  base::WeakPtr<NativeJavaScriptDialogRunner> weak = GetWeakPtr();
  [presenter presentKind:kind
                    title:title
                  message:base::SysUTF16ToNSString(message_text)
              defaultText:base::SysUTF16ToNSString(default_prompt_text)
        offersSuppression:offer_suppression
               completion:^(BOOL accepted, NSString* input, BOOL suppress) {
                 //
                 if (suppress && weak) {
                   weak->impl_->blocking = true;
                 }
                 [completion complete:accepted input:input];
               }];
}

void NativeJavaScriptDialogRunner::RunBeforeUnload(
    CefBrowserHostBase* browser,
    bool is_reload,
    const std::u16string& /*message_text*/,
    DialogClosedCallback callback) {
  CEF_REQUIRE_UIT();
  if (!web_contents() || !browser ||
      browser->GetWebContents() != web_contents() || !impl_->presenter) {
    std::move(callback).Run(false, std::u16string());
    return;
  }
  PCJavaScriptDialogCallback* completion = [PCJavaScriptDialogCallback new];
  completion->callback = std::move(callback);
  //
  //
  PCJavaScriptDialogPresenter* presenter = impl_->presenter;
  [presenter presentKind:PCJavaScriptDialogBeforeUnload
                    title:base::SysUTF16ToNSString(l10n_util::GetStringUTF16(
                              is_reload ? IDS_BEFORERELOAD_MESSAGEBOX_TITLE
                                        : IDS_BEFOREUNLOAD_MESSAGEBOX_TITLE))
                  message:base::SysUTF16ToNSString(l10n_util::GetStringUTF16(
                              IDS_BEFOREUNLOAD_MESSAGEBOX_MESSAGE))
              defaultText:@""
        offersSuppression:NO
               completion:^(BOOL accepted, NSString* input, BOOL) {
                 [completion complete:accepted input:input];
               }];
}

void NativeJavaScriptDialogRunner::Handle(
    bool accept,
    const std::u16string* prompt_override) {
  CEF_REQUIRE_UIT();
  PCJavaScriptDialogPresenter* presenter = impl_->presenter;
  [presenter handleAccepted:accept
             promptOverride:prompt_override
                                ? base::SysUTF16ToNSString(*prompt_override)
                                : nil];
}

void NativeJavaScriptDialogRunner::Cancel() {
  CEF_REQUIRE_UIT();
  PCJavaScriptDialogPresenter* presenter = impl_->presenter;
  [presenter cancel];
}

void NativeJavaScriptDialogRunner::PageHostWillDetach() {
  CEF_REQUIRE_UIT();
  PCJavaScriptDialogPresenter* presenter = impl_->presenter;
  [presenter pageHostWillDetach];
}

void NativeJavaScriptDialogRunner::PageHostDidAttach() {
  CEF_REQUIRE_UIT();
  PCJavaScriptDialogPresenter* presenter = impl_->presenter;
  [presenter pageHostDidAttach];
}

base::WeakPtr<NativeJavaScriptDialogRunner>
NativeJavaScriptDialogRunner::GetWeakPtr() {
  CEF_REQUIRE_UIT();
  return weak_ptr_factory_.GetWeakPtr();
}

void NativeJavaScriptDialogRunner::PrimaryPageChanged(content::Page&) {
  CEF_REQUIRE_UIT();
  impl_->displayed = 0;
  impl_->blocking = false;
}

void NativeJavaScriptDialogRunner::WebContentsDestroyed() {
  CEF_REQUIRE_UIT();
  weak_ptr_factory_.InvalidateWeakPtrs();
  Observe(nullptr);
  PCJavaScriptDialogPresenter* presenter = impl_->presenter;
  [presenter invalidate];
}

namespace {
// Chrome's repost warning (RepostFormWarningController) on the page's own
//
//
//
// continues the pending reload; Cancel, Escape, a refused sheet, a new load or
// the page leaving its window cancel it, as the controller's Cancel/Close do.
// A second warning while the sheet is open lets that sheet answer.
class RepostFormWarningSheet final
    : public content::WebContentsObserver,
      public content::WebContentsUserData<RepostFormWarningSheet> {
 public:
  ~RepostFormWarningSheet() override { [presenter_ invalidate]; }

  bool Show() {
    if (!presenter_) {
      return false;
    }
    // A sheet already open answers for the newest pending reload: Chromium
    // keeps one, so a second warning needs no second sheet.
    if (pending_) {
      return true;
    }
    pending_ = true;
    const int generation = generation_;
    base::WeakPtr<RepostFormWarningSheet> weak = weak_factory_.GetWeakPtr();
    [presenter_ presentKind:PCJavaScriptDialogConfirm
                      title:base::SysUTF16ToNSString(l10n_util::GetStringUTF16(
                                IDS_HTTP_POST_WARNING_TITLE))
                    message:base::SysUTF16ToNSString(
                                l10n_util::GetStringUTF16(IDS_HTTP_POST_WARNING))
                defaultText:@""
          offersSuppression:NO
                 completion:^(BOOL accepted, NSString*, BOOL) {
                   if (!weak || !weak->pending_ ||
                       weak->generation_ != generation || !weak->web_contents()) {
                     return;
                   }
                   weak->pending_ = false;
                   content::NavigationController& controller =
                       weak->web_contents()->GetController();
                   if (accepted) {
                     controller.ContinuePendingReload();
                   } else {
                     controller.CancelPendingReload();
                   }
                 }];
    return true;
  }

  // Closes an open sheet and cancels its reload.
  void Dismiss() {
    if (pending_ && web_contents()) {
      web_contents()->GetController().CancelPendingReload();
    }
    Retire();
  }

 private:
  friend WebContentsUserData;
  explicit RepostFormWarningSheet(content::WebContents* contents)
      : content::WebContentsObserver(contents),
        content::WebContentsUserData<RepostFormWarningSheet>(*contents) {
    NSView* page = contents->GetNativeView().GetNativeNSView();
    if (page) {
      presenter_ = [[PCJavaScriptDialogPresenter alloc] initWithPageView:page];
    }
  }

  // A new load supersedes the reload and cancels the open sheet, as the
  // controller's Close does.
  void DidStartLoading() override { Dismiss(); }
  void WebContentsDestroyed() override {
    Retire();
    [presenter_ invalidate];
  }
  // Stops the open sheet from answering; its completion no longer matches.
  void Retire() {
    if (!pending_) {
      return;
    }
    pending_ = false;
    ++generation_;
    [presenter_ cancel];
  }

  PCJavaScriptDialogPresenter* __strong presenter_;
  bool pending_ = false;
  int generation_ = 0;
  base::WeakPtrFactory<RepostFormWarningSheet> weak_factory_{this};
  WEB_CONTENTS_USER_DATA_KEY_DECL();
};

WEB_CONTENTS_USER_DATA_KEY_IMPL(RepostFormWarningSheet);
}  // namespace

bool ShowNativeRepostFormWarning(content::WebContents& contents) {
  CEF_REQUIRE_UIT();
  RepostFormWarningSheet::CreateForWebContents(&contents);
  return RepostFormWarningSheet::FromWebContents(&contents)->Show();
}

void DismissNativeRepostFormWarning(content::WebContents& contents) {
  CEF_REQUIRE_UIT();
  if (auto* sheet = RepostFormWarningSheet::FromWebContents(&contents)) {
    sheet->Dismiss();
  }
}

}  // namespace parc
