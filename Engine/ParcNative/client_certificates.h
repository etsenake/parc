// Copyright 2026 Parc contributors.
#ifndef PARC_NATIVE_CLIENT_CERTIFICATES_H_
#define PARC_NATIVE_CLIENT_CERTIFICATES_H_
namespace content {
class WebContents;
}
namespace parc {
// Install before navigation, on the actual native page. Chrome certificate
// policy and automatic selection run before this page-owned presentation hook.
void InstallNativeClientCertificates(content::WebContents&);
void SetNativeClientCertificatesAttached(content::WebContents&, bool attached);
}  // namespace parc
#endif
