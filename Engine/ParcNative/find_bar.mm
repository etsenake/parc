#import "find_bar.h"

#include <algorithm>
#include <cmath>
#include "base/check.h"
#include "base/functional/bind.h"
#include "base/functional/callback.h"
#include "base/strings/sys_string_conversions.h"
#include "chrome/browser/ui/find_bar/find_bar_controller.h"
#include "components/find_in_page/find_notification_details.h"
#include "components/find_in_page/find_tab_helper.h"
#include "components/find_in_page/find_types.h"
#include "content/public/browser/web_contents.h"
#include "ui/gfx/geometry/point.h"

@interface PCNativeFindDelegate : NSObject <PCNativeFindViewDelegate> {
 @public
  base::RepeatingCallback<void(PCNativeFindAction, NSString*)> action;
  base::RepeatingCallback<void(bool)> focus;
}
@end
@implementation PCNativeFindDelegate
- (void)findView:(PCNativeFindView*)view perform:(PCNativeFindAction)value text:(NSString*)text {
  // A native callback may synchronously destroy the controller/bar/bridge.
  auto callback = action;
  if (callback) callback.Run(value, text);
}
- (void)findView:(PCNativeFindView*)view didChangeFocus:(BOOL)value {
  auto callback = focus;
  if (callback) callback.Run(value);
}
@end

namespace parc {
NativeFindBar::NativeFindBar(NativeFindBarHost& host) : host_(host) {
  CHECK(NSThread.isMainThread);
  view_ = [[PCNativeFindView alloc] initWithFrame:NSZeroRect];
  PCNativeFindDelegate* bridge = [[PCNativeFindDelegate alloc] init];
  bridge->action = base::BindRepeating(&NativeFindBar::OnNativeAction,
                                      weak_factory_.GetWeakPtr());
  bridge->focus = base::BindRepeating(&NativeFindBar::OnNativeFocus,
                                     weak_factory_.GetWeakPtr());
  delegate_ = bridge;
  view_.delegate = bridge;
}
NativeFindBar::~NativeFindBar() {
  CHECK(NSThread.isMainThread);
  weak_factory_.InvalidateWeakPtrs();
  controller_ = nullptr;
  [view_ invalidate];
  delegate_ = nil;
}
FindBarController* NativeFindBar::GetFindBarController() const { return controller_; }
void NativeFindBar::SetFindBarController(FindBarController* controller) {
  CHECK(controller);
  CHECK(!controller_ || controller_ == controller);
  controller_ = controller;
}
bool NativeFindBar::RefreshContext() {
  if (!controller_ || !controller_->web_contents()) {
    [view_ attachToContainer:nil topInset:10 focusManager:nil focusKey:nil pageFocusKey:nil];
    return false;
  }
  const bool visible = view_.isPresented;
  auto weak = weak_factory_.GetWeakPtr();
  NativeFindBarContext context = host_->GetFindBarContext(controller_->web_contents());
  if (!weak) return false;
  bool attached = [view_ attachToContainer:context.container topInset:context.top_inset
      focusManager:context.focus_manager focusKey:context.find_key pageFocusKey:context.page_key];
  // Hiding the previous field can deliver a focus callback that destroys its
  // owning controller. Do not touch bridge members after that boundary.
  if (!weak) return false;
  if (attached && visible) [view_ presentTakingFocus:NO];
  if (!weak) return false;
  if (visible != view_.isPresented && controller_) controller_->OnFindBarVisibilityChanged();
  return weak && attached;
}
void NativeFindBar::Show(bool animate, bool focus) {
  // No recovered animation curve yet. Present synchronously and honestly.
  auto weak = weak_factory_.GetWeakPtr();
  if (!RefreshContext()) return;
  bool was_visible = view_.isPresented;
  [view_ presentTakingFocus:focus];
  if (weak && !was_visible && view_.isPresented && controller_) {
    controller_->OnFindBarVisibilityChanged();
  }
}
void NativeFindBar::Hide(bool animate) {
  bool was_visible = view_.isPresented;
  auto weak = weak_factory_.GetWeakPtr();
  [view_ dismiss];
  if (weak && was_visible && controller_) controller_->OnFindBarVisibilityChanged();
}
void NativeFindBar::SetFocusAndSelection() { [view_ focusAndSelectAll]; }
void NativeFindBar::ClearResults(const find_in_page::FindNotificationDetails&) {
  // Preserve the global Mac Find-pasteboard query, as upstream FindBarHost does.
  [view_ setMatchCount:-1 ordinal:-1];
}
void NativeFindBar::StopAnimation() { /* Presentation is synchronous. */ }
void NativeFindBar::MoveWindowIfNecessary() { RefreshContext(); }
void NativeFindBar::SetFindTextAndSelectedRange(const std::u16string& text,
                                               const gfx::Range& selection) {
  text_ = text;
  view_.text = base::SysUTF16ToNSString(text_);
  if (selection.IsValid()) {
    view_.selectedRange = NSMakeRange(selection.GetMin(), selection.length());
  }
}
std::u16string_view NativeFindBar::GetFindText() const { return text_; }
gfx::Range NativeFindBar::GetSelectedRange() const {
  NSRange range = view_.selectedRange;
  return gfx::Range(range.location, range.location + range.length);
}
void NativeFindBar::UpdateUIForFindResult(
    const find_in_page::FindNotificationDetails& result,
    const std::u16string& text) {
  // Empty result text can mean navigation reset while user text is retained.
  // Chromium FindBarView uses the same nonempty-result update condition.
  if (!text.empty() && text_ != text && !view_.hasMarkedText) {
    text_ = text;
    view_.text = base::SysUTF16ToNSString(text_);
    view_.selectedRange = NSMakeRange(0, text_.size());
  }
  bool valid = !text.empty() && result.number_of_matches() >= 0 && result.active_match_ordinal() >= 0;
  [view_ setMatchCount:valid ? result.number_of_matches() : -1
               ordinal:result.active_match_ordinal()];
}
void NativeFindBar::AudibleAlert() {
  // Pinned Chrome counts the notification but plays no sound on macOS.
  ++audible_alerts_;
}
bool NativeFindBar::IsFindBarVisible() const { return view_.isPresented; }
void NativeFindBar::RestoreSavedFocus() { [view_ restoreSavedFocus]; }
bool NativeFindBar::HasGlobalFindPasteboard() const { return true; }
void NativeFindBar::UpdateFindBarForChangedWebContents() { RefreshContext(); }
bool NativeFindBar::CanPopulateFromSelectedText() { return true; }
const FindBarTesting* NativeFindBar::GetFindBarTesting() const { return this; }
bool NativeFindBar::HasFocus() const { return view_.hasFindFocus; }
void NativeFindBar::CloseOverlappingBubbles() { host_->CloseFindOverlappingBubbles(); }
views::Widget* NativeFindBar::GetHostWidget() { return nullptr; }  // Real AppKit host.
bool NativeFindBar::GetFindBarWindowInfo(gfx::Point* point, bool* fully_visible) const {
  bool visible = view_.isPresented && view_.window.isVisible && !view_.isHiddenOrHasHiddenAncestor;
  if (point) *point = gfx::Point();
  if (fully_visible) *fully_visible = false;
  if (!visible) return false;
  NSRect rect = [view_.window convertRectToScreen:[view_ convertRect:view_.bounds toView:nil]];
  if (point) *point = gfx::Point(std::lround(rect.origin.x), std::lround(rect.origin.y));
  if (fully_visible) *fully_visible = NSContainsRect(view_.visibleRect, view_.bounds);
  return true;
}
std::u16string_view NativeFindBar::GetFindSelectedText() const {
  NSRange range = view_.selectedRange;
  selected_text_ = text_.substr(std::min(range.location, text_.size()), range.length);
  return selected_text_;
}
std::u16string_view NativeFindBar::GetMatchCountText() const {
  count_text_ = base::SysNSStringToUTF16(view_.matchCountText);
  return count_text_;
}
int NativeFindBar::GetContentsWidth() const { return std::lround(view_.bounds.size.width); }
size_t NativeFindBar::GetAudibleAlertCount() const { return audible_alerts_; }
void NativeFindBar::OnNativeAction(PCNativeFindAction action, NSString* text) {
  if (!controller_) return;
  content::WebContents* contents = controller_->web_contents();
  if (!contents) return;
  auto* helper = find_in_page::FindTabHelper::FromWebContents(contents);
  if (!helper) return;
  if (action == PCNativeFindClose) {
    controller_->EndFindSession(find_in_page::SelectionAction::kKeep,
                                find_in_page::ResultAction::kKeep);
    return;
  }
  std::u16string query = base::SysNSStringToUTF16(text);
  if (action != PCNativeFindQueryChanged && query.empty()) return;
  text_ = query;
  if (action == PCNativeFindQueryChanged) {
    auto weak = weak_factory_.GetWeakPtr();
    controller_->OnUserChangedFindText(query);
    if (!weak || !controller_ || controller_->web_contents() != contents) return;
    helper = find_in_page::FindTabHelper::FromWebContents(contents);
    if (!helper) return;
  }
  helper->StartFinding(query, action != PCNativeFindPrevious,
                      /*case_sensitive=*/false, /*find_match=*/true);
}
void NativeFindBar::OnNativeFocus(bool focused) {
  if (!controller_ || !controller_->web_contents()) return;
  auto* helper = find_in_page::FindTabHelper::FromWebContents(controller_->web_contents());
  if (helper) helper->set_find_ui_focused(focused);
}
}  // namespace parc
