// Copyright 2019 The Chromium Authors

#include <utility>

#include "chrome/browser/ui/views/global_media_controls/media_dialog_view.h"
#include "chrome/browser/ui/global_media_controls/media_notification_service.h"
#include "components/soda/soda_installer.h"
#include "ui/views/widget/widget.h"
#include "base/metrics/histogram_functions.h"
#include "components/global_media_controls/public/constants.h"
#include "components/global_media_controls/public/media_item_manager.h"

views::Widget* MediaDialogView::CreateDialogForNativePage(
    gfx::NativeView parent,
    const gfx::Rect& bounds,
    MediaNotificationService* service,
    Profile* profile,
    content::WebContents* contents,
    base::UnguessableToken token,
    base::RepeatingCallback<bool()> native_guard) {
  DCHECK(service);
  DCHECK(parent);
  DCHECK(contents);
  HideDialog();
  if (instance_ || !native_guard || !native_guard.Run() ||
      (!token.is_empty() && !service->PrepareNativeDialog(token)))
    return nullptr;
  auto* dialog = new MediaDialogView(
      views::BubbleAnchor(), views::BubbleBorder::TOP_CENTER, service, profile,
      contents, global_media_controls::GlobalMediaControlsEntryPoint::kPresentation);
  instance_ = dialog;
  dialog->native_guard_ = std::move(native_guard);
  dialog->set_parent_window(parent);
  dialog->SetAnchorRect(bounds);
  auto* widget = views::BubbleDialogDelegateView::CreateBubble(dialog);
  if (instance_ != dialog)
    return nullptr;
  base::UmaHistogramBoolean("Media.GlobalMediaControls.RepeatUsage",
                            has_been_opened_);
  base::UmaHistogramEnumeration(
      "Media.GlobalMediaControls.EntryPoint",
      global_media_controls::GlobalMediaControlsEntryPoint::kPresentation);
  has_been_opened_ = true;
  return widget;
}

bool MediaDialogView::IsNativeDialogCurrent(views::Widget* widget) {
  return widget && instance_ && instance_->GetWidget() == widget;
}

void MediaDialogView::CloseNativeDialog(views::Widget* widget) {
  if (IsNativeDialogCurrent(widget))
    HideDialog();
}

void MediaDialogView::ForgetNativeDialogForDestroying(views::Widget* widget) {
  if (!IsNativeDialogCurrent(widget))
    return;
  auto* old = instance_;
  auto* service = old->service_.get();
  instance_ = nullptr;
  speech::SodaInstaller::GetInstance()->RemoveObserver(old);
  service->media_item_manager()->SetDialogDelegate(nullptr);
}
