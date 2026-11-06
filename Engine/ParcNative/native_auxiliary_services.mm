// Copyright 2026 Parc contributors.
#include "native_auxiliary_services.h"

#import <AppKit/AppKit.h>

#include "base/functional/bind.h"
#include "base/strings/sys_string_conversions.h"
#include "client_certificates.h"
#include "components/javascript_dialogs/app_modal_dialog_controller.h"
#include "components/javascript_dialogs/app_modal_dialog_manager.h"
#include "components/javascript_dialogs/app_modal_dialog_view.h"
#include "content/public/browser/web_contents.h"
#include "content/public/browser/web_contents_delegate.h"
#include "folder_upload.h"
#include "http_auth.h"
#include "native_auxiliary_page.h"
#import "window_security_reservation.h"

@interface PCAuxiliaryDialogActions : NSObject {
 @public
  base::RepeatingCallback<void(bool)> action;
}
- (void)accept:(id)sender;
- (void)cancel:(id)sender;
@end
@implementation PCAuxiliaryDialogActions
- (void)accept:(id)sender {
  auto callback = action;
  if (callback) {
    callback.Run(true);
  }
}
- (void)cancel:(id)sender {
  auto callback = action;
  if (callback) {
    callback.Run(false);
  }
}
@end

namespace parc {
namespace {
// AppModalDialogQueue and the real controller still own ordering, suppression,
//
// supplied-view attachment justify a page-bound sheet; exact visual parity is
// deliberately not inferred from that evidence.
class Dialog final : public javascript_dialogs::AppModalDialogView {
 public:
  explicit Dialog(
      std::unique_ptr<javascript_dialogs::AppModalDialogController> model,
      std::shared_ptr<NativeAuxiliaryPage> lease)
      : model_(std::move(model)), lease_(std::move(lease)) {
    model_->SetNativeDecisionValidator(base::BindRepeating(
        [](std::shared_ptr<NativeAuxiliaryPage> lease) {
          // A subsequent real queue item may select a different tab or own a
          // sheet. Only loss of this captured ownership invalidates the prior
          // decision at this post-queue boundary; never acquire a newer lease.
          return lease && lease->IsValid();
        },
        lease_));
  }
  ~Dialog() override {
    if (security_) {
      [NSNotificationCenter.defaultCenter removeObserver:security_];
    }
  }
  void ShowAppModalDialog() override {
    if (!lease_ || !lease_->IsValid() || !model_->IsValid()) {
      Finish(false, true);
      return;
    }
    // Match Chromium's real AppModal activation route. For docked tools the
    // actual DevToolsWindow delegate activates the inspected page; no
    // key-window lookup or synthetic tab is involved. Run after view_ was
    // installed so a reentrant cancellation has a real view to close.
    auto weak = weak_factory_.GetWeakPtr();
    auto* contents = model_->web_contents();
    if (!contents || !contents->GetDelegate()) {
      Finish(false, true);
      return;
    }
    contents->GetDelegate()->ActivateContents(contents);
    if (!weak) {
      return;
    }
    if (!lease_->IsActive() || !model_->IsValid()) {
      Finish(false, true);
      return;
    }
    parent_ = lease_->window();
    if (!parent_.visible || parent_.attachedSheet ||
        PCNativeWindowHasSecurityReservation(parent_)) {
      Finish(false, true);
      return;
    }
    invalidated_ = lease_->OnInvalidated(
        base::BindRepeating(&Dialog::CloseAppModalDialog, weak));
    auto reservation =
        [PCNativeWindowSecurityReservation acquireForWindow:parent_];
    if (!weak) {
      [reservation invalidate];
      return;
    }
    reservation_ = reservation;
    if (!lease_->IsValid() || !reservation.isOnlyReservation ||
        parent_.attachedSheet) {
      Finish(false, true);
      return;
    }
    security_ = [NSNotificationCenter.defaultCenter
        addObserverForName:PCNativeWindowSecurityStateChanged
                    object:parent_
                     queue:nil
                usingBlock:^(NSNotification*) {
                  if (weak && !weak->reservation_.isOnlyReservation) {
                    weak->CloseAppModalDialog();
                  }
                }];
    const bool prompt = model_->javascript_dialog_type() ==
                        content::JAVASCRIPT_DIALOG_TYPE_PROMPT;
    const bool suppress = model_->display_suppress_checkbox();
    const CGFloat height = 190 + (prompt ? 34 : 0) + (suppress ? 28 : 0);
    panel_ = [[NSPanel alloc] initWithContentRect:NSMakeRect(0, 0, 440, height)
                                        styleMask:NSWindowStyleMaskTitled
                                          backing:NSBackingStoreBuffered
                                            defer:NO];
    panel_.releasedWhenClosed = NO;
    panel_.title = base::SysUTF16ToNSString(model_->title());
    NSView* content = panel_.contentView;
    NSTextField* title = [NSTextField labelWithString:panel_.title];
    title.font = [NSFont boldSystemFontOfSize:14];
    title.frame = NSMakeRect(20, height - 46, 400, 26);
    [content addSubview:title];
    // Preserve the actual model's complete (upstream-bounded) message. Long
    // prompts remain readable and selectable rather than being clipped.
    NSScrollView* scroll = [[NSScrollView alloc]
        initWithFrame:NSMakeRect(20, height - 120, 400, 70)];
    scroll.hasVerticalScroller = YES;
    scroll.drawsBackground = NO;
    NSTextView* message = [[NSTextView alloc] initWithFrame:scroll.bounds];
    message.editable = NO;
    message.selectable = YES;
    message.drawsBackground = NO;
    message.font = [NSFont systemFontOfSize:13];
    message.textColor = NSColor.labelColor;
    message.string = base::SysUTF16ToNSString(model_->message_text());
    message.autoresizingMask = NSViewWidthSizable;
    message.textContainer.widthTracksTextView = YES;
    scroll.documentView = message;
    [content addSubview:scroll];
    CGFloat y = height - 154;
    if (prompt) {
      input_ = [[NSTextField alloc] initWithFrame:NSMakeRect(20, y, 400, 24)];
      input_.stringValue =
          base::SysUTF16ToNSString(model_->default_prompt_text());
      input_.accessibilityLabel = @"Response";
      [content addSubview:input_];
      panel_.initialFirstResponder = input_;
      y -= 30;
    }
    if (suppress) {
      suppress_ =
          [NSButton checkboxWithTitle:
                        @"Prevent this page from creating additional dialogs"
                               target:nil
                               action:nil];
      suppress_.frame = NSMakeRect(20, y, 400, 24);
      [content addSubview:suppress_];
    }
    actions_ = [PCAuxiliaryDialogActions new];
    actions_->action = base::BindRepeating(
        [](base::WeakPtr<Dialog> self, bool accepted) {
          if (self) {
            self->Finish(accepted, false);
          }
        },
        weak);
    NSString* primary = model_->is_before_unload_dialog()
                            ? (model_->is_reload() ? @"Reload" : @"Leave Page")
                            : @"OK";
    NSButton* accept = [NSButton buttonWithTitle:primary
                                          target:actions_
                                          action:@selector(accept:)];
    accept.frame = NSMakeRect(318, 18, 102, 30);
    accept.keyEquivalent = @"\r";
    [content addSubview:accept];
    panel_.defaultButtonCell = accept.cell;
    NSButton* cancel = [NSButton
        buttonWithTitle:model_->is_before_unload_dialog() ? @"Stay" : @"Cancel"
                 target:actions_
                 action:@selector(cancel:)];
    cancel.frame = NSMakeRect(206, 18, 102, 30);
    cancel.keyEquivalent = @"\033";
    if (model_->javascript_dialog_type() ==
        content::JAVASCRIPT_DIALOG_TYPE_ALERT) {
      cancel.title = @"Close";
    }
    [content addSubview:cancel];
    showing_ = true;
    [parent_ beginSheet:panel_
        completionHandler:^(NSModalResponse) {
          if (weak) {
            weak->CloseAppModalDialog();
          }
        }];
  }
  void ActivateAppModalDialog() override {
    if (!showing_ || !lease_->IsValid() || !model_->IsValid()) {
      return;
    }
    auto weak = weak_factory_.GetWeakPtr();
    auto* contents = model_->web_contents();
    if (contents && contents->GetDelegate()) {
      contents->GetDelegate()->ActivateContents(contents);
    }
    if (!weak) {
      return;
    }
    if (!lease_->IsActive() || !model_->IsValid()) {
      Finish(false, true);
      return;
    }
    [panel_ makeKeyWindow];
  }
  void CloseAppModalDialog() override { Finish(false, true); }
  void AcceptAppModalDialog() override { Finish(true, false); }
  void CancelAppModalDialog() override { Finish(false, false); }
  bool IsShowing() const override { return showing_; }

 private:
  void Finish(bool accepted, bool interrupted) {
    if (finished_) {
      return;
    }
    finished_ = true;
    showing_ = false;
    weak_factory_.InvalidateWeakPtrs();
    auto model = std::move(model_);
    auto lease = std::move(lease_);
    const auto text = input_ ? base::SysNSStringToUTF16(input_.stringValue)
                             : std::u16string();
    const bool suppress = suppress_.state == NSControlStateValueOn;
    invalidated_ = {};
    if (actions_) {
      actions_->action.Reset();
    }
    if (security_) {
      [NSNotificationCenter.defaultCenter removeObserver:security_];
      security_ = nil;
    }
    auto panel = panel_;
    panel_ = nil;
    if (panel.sheetParent) {
      [panel.sheetParent endSheet:panel];
    }
    [panel orderOut:nil];
    auto reservation = reservation_;
    reservation_ = nil;
    NSWindow* parent = parent_;
    [reservation invalidate];
    // A reservation observer may detach the exact page before the decision.
    interrupted = interrupted || !lease || !lease->IsActive() ||
                  !model->IsValid() || !parent || lease->window() != parent ||
                  parent.attachedSheet ||
                  PCNativeWindowHasSecurityReservation(parent);
    if (interrupted) {
      model->OnClose();
    } else if (accepted) {
      model->OnAccept(text, suppress);
    } else {
      model->OnCancel(suppress);
    }
    model.reset();  // Real controller releases the queue before view deletion.
    delete this;
  }
  std::unique_ptr<javascript_dialogs::AppModalDialogController> model_;
  std::shared_ptr<NativeAuxiliaryPage> lease_;
  base::CallbackListSubscription invalidated_;
  NSWindow* __weak parent_;
  NSPanel* __strong panel_;
  NSTextField* __strong input_;
  NSButton* __strong suppress_;
  PCAuxiliaryDialogActions* __strong actions_;
  PCNativeWindowSecurityReservation* __strong reservation_;
  id __strong security_;
  bool showing_ = false;
  bool finished_ = false;
  base::WeakPtrFactory<Dialog> weak_factory_{this};
};
}  // namespace
void PrepareNativeAuxiliaryServices(content::WebContents& contents) {
  MarkNativeAuxiliaryRoute(contents);
  InstallNativeHTTPAuth(contents);
  InstallNativeFolderUpload(contents);
  InstallNativeClientCertificates(contents);
  using Manager = javascript_dialogs::AppModalDialogManager;
  Manager::SetNativeViewFactoryProvider(
      contents,
      base::BindRepeating(
          [](base::WeakPtr<content::WebContents> contents)
              -> Manager::AppModalViewFactory {
            auto lease = contents ? GetNativeAuxiliaryPage(*contents) : nullptr;
            return base::BindRepeating(
                [](std::shared_ptr<NativeAuxiliaryPage> lease,
                   std::unique_ptr<javascript_dialogs::AppModalDialogController>
                       controller) -> javascript_dialogs::AppModalDialogView* {
                  return new Dialog(std::move(controller), std::move(lease));
                },
                std::move(lease));
          },
          contents.GetWeakPtr()));
}
}  // namespace parc
