// Copyright 2026 Parc contributors.
#ifndef PARC_NATIVE_CERTIFICATE_VIEWER_H_
#define PARC_NATIVE_CERTIFICATE_VIEWER_H_
namespace content {
class WebContents;
}
namespace parc {
void InstallNativeServerCertificateViewer(content::WebContents& contents);
// Set false before native reparenting. A later attach never revives a request.
void SetNativeServerCertificateViewerAttached(content::WebContents&, bool);
}  // namespace parc
#endif
