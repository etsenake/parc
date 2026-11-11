// Copyright 2026 Parc contributors.
#ifndef PARC_NATIVE_JAVASCRIPT_DIALOG_MANAGER_H_
#define PARC_NATIVE_JAVASCRIPT_DIALOG_MANAGER_H_
namespace content {
class JavaScriptDialogManager;
class WebContents;
}  // namespace content
namespace parc {
// Page-bound alert, confirm, prompt and beforeunload sheets for one actual
// native page; no BrowserView, tab-modal or app-modal fallback. Install before
// the first navigation. The page starts detached: requests are refused until
// the page's real host attaches it, and detaching cancels the open sheet.
void InstallNativeJavaScriptDialogs(content::WebContents& contents);
void SetNativeJavaScriptDialogsAttached(content::WebContents& contents,
                                        bool attached);
// For the page's WebContentsDelegate. Null only when nothing was installed;
// content then cancels the dialog rather than consenting to it.
content::JavaScriptDialogManager* NativeJavaScriptDialogManager(
    content::WebContents& contents);
}  // namespace parc
#endif  // PARC_NATIVE_JAVASCRIPT_DIALOG_MANAGER_H_
