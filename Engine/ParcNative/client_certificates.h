// Copyright 2026 Parc contributors.
#ifndef PARC_NATIVE_CLIENT_CERTIFICATES_H_
#define PARC_NATIVE_CLIENT_CERTIFICATES_H_
#include <memory>

#include "base/functional/callback.h"
#include "net/ssl/client_cert_identity.h"
namespace content {
class ClientCertificateDelegate;
class WebContents;
}
namespace net {
class SSLCertRequestInfo;
}
namespace parc {
// Install before navigation, on the actual native page.
void InstallNativeClientCertificates(content::WebContents&);
// ShowSSLClientCertificateSelector for every page, after Chrome certificate
// policy and automatic selection: installed pages get the page-owned native
// presentation, any other page Chromium's Views selector.
base::OnceClosure ShowClientCertificateSelector(
    content::WebContents* contents,
    net::SSLCertRequestInfo* info,
    net::ClientCertIdentityList identities,
    std::unique_ptr<content::ClientCertificateDelegate> delegate);
void SetNativeClientCertificatesAttached(content::WebContents&, bool attached);
}  // namespace parc
#endif
