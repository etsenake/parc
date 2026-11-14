// Copyright 2026 Parc contributors.
#include "javascript_dialog_manager.h"

#include <utility>

#include "base/functional/callback.h"
#include "base/memory/weak_ptr.h"
#include "base/strings/sys_string_conversions.h"
#include "components/javascript_dialogs/app_modal_dialog_manager.h"
#include "components/strings/grit/components_strings.h"
#include "content/public/browser/browser_thread.h"
#include "content/public/browser/javascript_dialog_manager.h"
#include "content/public/browser/navigation_controller.h"
#include "content/public/browser/render_frame_host.h"
#include "content/public/browser/web_contents.h"
#include "content/public/browser/web_contents_observer.h"
#include "content/public/browser/web_contents_user_data.h"
#include "ui/base/l10n/l10n_util.h"
#import "javascript_dialog_presenter.h"
#include "native_repost_form_warning_api.h"

// The block owns this box, not the manager. A result can synchronously destroy
// the page and its manager without leaving a callback into their storage.
@interface PCJavaScriptDialogCallback : NSObject {
 @public
  content::JavaScriptDialogManager::DialogClosedCallback callback;
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
class NativeJavaScriptDialogs final
    : public content::JavaScriptDialogManager,
      public content::WebContentsObserver,
      public content::WebContentsUserData<NativeJavaScriptDialogs> {
 public:
  ~NativeJavaScriptDialogs() override { [presenter_ invalidate]; }

  void SetAttached(bool attached) {
    if (attached) {
      [presenter_ pageHostDidAttach];
    } else {
      [presenter_ pageHostWillDetach];
    }
  }

  void RunJavaScriptDialog(content::WebContents* contents,
                           content::RenderFrameHost* frame,
                           content::JavaScriptDialogType type,
                           const std::u16string& message_text,
                           const std::u16string& default_prompt_text,
                           DialogClosedCallback callback,
                           bool* did_suppress_message) override {
    DCHECK_CURRENTLY_ON(content::BrowserThread::UI);
    *did_suppress_message = false;
    if (!IsSource(contents, frame)) {
      std::move(callback).Run(false, std::u16string());
      return;
    }
    PCJavaScriptDialogKind kind;
    switch (type) {
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
    if (blocking_) {
      *did_suppress_message = true;
      return;
    }
    const bool offer_suppression = ++displayed_ > 5;
    PCJavaScriptDialogCallback* completion = [PCJavaScriptDialogCallback new];
    completion->callback = std::move(callback);
    content::RenderFrameHost* main = contents->GetPrimaryMainFrame();
    NSString* title = base::SysUTF16ToNSString(
        javascript_dialogs::AppModalDialogManager::GetSiteFrameTitle(
            main->GetLastCommittedURL(), main->GetLastCommittedOrigin(),
            frame->GetLastCommittedOrigin()));
    PCJavaScriptDialogPresenter* presenter = presenter_;
    base::WeakPtr<NativeJavaScriptDialogs> weak = weak_factory_.GetWeakPtr();
    [presenter presentKind:kind
                      title:title
                    message:base::SysUTF16ToNSString(message_text)
                defaultText:base::SysUTF16ToNSString(default_prompt_text)
          offersSuppression:offer_suppression
                 completion:^(BOOL accepted, NSString* input, BOOL suppress) {
                   if (suppress && weak) {
                     weak->blocking_ = true;
                   }
                   [completion complete:accepted input:input];
                 }];
  }

  void RunBeforeUnloadDialog(content::WebContents* contents,
                             content::RenderFrameHost* frame,
                             bool is_reload,
                             DialogClosedCallback callback) override {
    DCHECK_CURRENTLY_ON(content::BrowserThread::UI);
    if (!IsSource(contents, frame)) {
      std::move(callback).Run(false, std::u16string());
      return;
    }
    PCJavaScriptDialogCallback* completion = [PCJavaScriptDialogCallback new];
    completion->callback = std::move(callback);
    PCJavaScriptDialogPresenter* presenter = presenter_;
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

  bool HandleJavaScriptDialog(content::WebContents* contents,
                              bool accept,
                              const std::u16string* prompt_override) override {
    DCHECK_CURRENTLY_ON(content::BrowserThread::UI);
    PCJavaScriptDialogPresenter* presenter = presenter_;
    if (contents != web_contents() || !presenter.presenting) {
      return false;
    }
    [presenter handleAccepted:accept
               promptOverride:prompt_override
                                  ? base::SysUTF16ToNSString(*prompt_override)
                                  : nil];
    return true;
  }

  void CancelDialogs(content::WebContents* contents,
                     bool reset_state) override {
    DCHECK_CURRENTLY_ON(content::BrowserThread::UI);
    if (contents != web_contents()) {
      return;
    }
    // Before cancelling: its completion may destroy this manager.
    if (reset_state) {
      displayed_ = 0;
      blocking_ = false;
    }
    [presenter_ cancel];
  }

 private:
  friend WebContentsUserData;
  explicit NativeJavaScriptDialogs(content::WebContents* contents)
      : content::WebContentsObserver(contents),
        content::WebContentsUserData<NativeJavaScriptDialogs>(*contents) {
    NSView* page = contents->GetNativeView().GetNativeNSView();
    if (page) {
      presenter_ = [[PCJavaScriptDialogPresenter alloc] initWithPageView:page];
      [presenter_ pageHostWillDetach];
    }
  }

  // Only this page's own frames may ask, and only while it has a presenter.
  bool IsSource(content::WebContents* contents,
                content::RenderFrameHost* frame) const {
    return presenter_ && contents && contents == web_contents() && frame &&
           content::WebContents::FromRenderFrameHost(frame) == contents;
  }

  void PrimaryPageChanged(content::Page&) override {
    displayed_ = 0;
    blocking_ = false;
  }

  void WebContentsDestroyed() override {
    weak_factory_.InvalidateWeakPtrs();
    Observe(nullptr);
    [presenter_ invalidate];
  }

  PCJavaScriptDialogPresenter* __strong presenter_;
  int displayed_ = 0;
  bool blocking_ = false;
  base::WeakPtrFactory<NativeJavaScriptDialogs> weak_factory_{this};
  WEB_CONTENTS_USER_DATA_KEY_DECL();
};

WEB_CONTENTS_USER_DATA_KEY_IMPL(NativeJavaScriptDialogs);
}  // namespace

void InstallNativeJavaScriptDialogs(content::WebContents& contents) {
  DCHECK_CURRENTLY_ON(content::BrowserThread::UI);
  NativeJavaScriptDialogs::CreateForWebContents(&contents);
}

void SetNativeJavaScriptDialogsAttached(content::WebContents& contents,
                                        bool attached) {
  DCHECK_CURRENTLY_ON(content::BrowserThread::UI);
  if (auto* dialogs = NativeJavaScriptDialogs::FromWebContents(&contents)) {
    dialogs->SetAttached(attached);
  }
}

content::JavaScriptDialogManager* NativeJavaScriptDialogManager(
    content::WebContents& contents) {
  DCHECK_CURRENTLY_ON(content::BrowserThread::UI);
  return NativeJavaScriptDialogs::FromWebContents(&contents);
}

namespace {
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
  DCHECK_CURRENTLY_ON(content::BrowserThread::UI);
  RepostFormWarningSheet::CreateForWebContents(&contents);
  return RepostFormWarningSheet::FromWebContents(&contents)->Show();
}

void DismissNativeRepostFormWarning(content::WebContents& contents) {
  DCHECK_CURRENTLY_ON(content::BrowserThread::UI);
  if (auto* sheet = RepostFormWarningSheet::FromWebContents(&contents)) {
    sheet->Dismiss();
  }
}

}  // namespace parc
