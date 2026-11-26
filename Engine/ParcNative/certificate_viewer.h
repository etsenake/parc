// Copyright 2026 Parc contributors.
#ifndef PARC_NATIVE_CERTIFICATE_VIEWER_H_
#define PARC_NATIVE_CERTIFICATE_VIEWER_H_
#include "ui/gfx/native_ui_types.h"
namespace content {
class WebContents;
}
namespace net {
class X509Certificate;
}
namespace parc {
void InstallNativeServerCertificateViewer(content::WebContents& contents);
bool ShowServerCertificateViewer(content::WebContents* contents,
                                 gfx::NativeWindow parent,
                                 net::X509Certificate* certificate);
// Set false before native reparenting. A later attach never revives a request.
void SetNativeServerCertificateViewerAttached(content::WebContents&, bool);
}  // namespace parc
#endif
