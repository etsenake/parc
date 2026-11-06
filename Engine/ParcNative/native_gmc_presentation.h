// Copyright 2026 Parc contributors.
#ifndef PARC_NATIVE_GMC_PRESENTATION_H_
#define PARC_NATIVE_GMC_PRESENTATION_H_
namespace content { class WebContents; }
namespace parc {
void InstallNativeGmcPresentationHandler();
bool CloseNativeGmcPresentationForPage(content::WebContents* contents);
}  // namespace parc
#endif
