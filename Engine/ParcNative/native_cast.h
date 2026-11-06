// Copyright 2026 Parc contributors.
#ifndef PARC_NATIVE_CAST_H_
#define PARC_NATIVE_CAST_H_
namespace content {
class WebContents;
}
namespace parc {
bool CloseNativeCastForPage(content::WebContents* contents);
bool CanShowNativeCast(content::WebContents* contents);
bool ShowNativeCast(content::WebContents* contents);
}  // namespace parc
#endif
