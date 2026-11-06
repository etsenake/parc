// Copyright 2026 Parc contributors.
#ifndef PARC_NATIVE_AUXILIARY_SERVICES_H_
#define PARC_NATIVE_AUXILIARY_SERVICES_H_
namespace content {
class WebContents;
}
namespace parc {
// Called for the actual main tools before first navigation. An unattached
// native auxiliary page is refused by native factories, never routed through
// CEF's window/focused-browser fallback. Ordinary page factories are unchanged.
void PrepareNativeAuxiliaryServices(content::WebContents&);
bool HasNativeAuxiliaryRoute(content::WebContents&);
}  // namespace parc
#endif
