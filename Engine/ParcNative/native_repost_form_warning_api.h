// Copyright 2026 Parc contributors.
#ifndef PARC_NATIVE_NATIVE_REPOST_FORM_WARNING_API_H_
#define PARC_NATIVE_NATIVE_REPOST_FORM_WARNING_API_H_
namespace content { class WebContents; }
namespace parc {
// Chrome's repost warning for a Parc page on its own alert sheet. False when
// the page has no native view; the caller then keeps Chrome's dialog. A page
// that cannot show the sheet (no window, another sheet up) cancels the reload.
bool ShowNativeRepostFormWarning(content::WebContents& contents);
// Before the page leaves its host: an open warning closes and cancels.
void DismissNativeRepostFormWarning(content::WebContents& contents);
}
#endif  // PARC_NATIVE_NATIVE_REPOST_FORM_WARNING_API_H_
