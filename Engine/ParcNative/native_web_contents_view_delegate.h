// Copyright 2026 Parc contributors.
#ifndef PARC_NATIVE_NATIVE_WEB_CONTENTS_VIEW_DELEGATE_H_
#define PARC_NATIVE_NATIVE_WEB_CONTENTS_VIEW_DELEGATE_H_

#include <memory>

namespace content {
class WebContents;
class WebContentsViewDelegate;
}  // namespace content

namespace parc {
// Chrome's Mac view delegate for every WebContents, with Parc's native history
// swipe delegate in place of Chrome's, so a page never has two swipers.
std::unique_ptr<content::WebContentsViewDelegate>
CreateNativeWebContentsViewDelegate(content::WebContents* web_contents);
}  // namespace parc

#endif  // PARC_NATIVE_NATIVE_WEB_CONTENTS_VIEW_DELEGATE_H_
