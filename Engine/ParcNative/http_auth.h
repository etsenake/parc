// Copyright 2026 Parc contributors.
#ifndef PARC_NATIVE_HTTP_AUTH_H_
#define PARC_NATIVE_HTTP_AUTH_H_
namespace content {
class WebContents;
}
namespace parc {
// UI-thread lifecycle seam. Install on the actual native WebContents before
// navigation. Closing the attachment gate cancels only requests captured for
// that page; a late reply cannot authorize a page transferred to another owner.
void InstallNativeHTTPAuth(content::WebContents& contents);
void SetNativeHTTPAuthAttached(content::WebContents& contents, bool attached);
}  // namespace parc
#endif
