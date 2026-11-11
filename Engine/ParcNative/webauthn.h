// Copyright 2026 Parc contributors.
#ifndef PARC_NATIVE_WEBAUTHN_H_
#define PARC_NATIVE_WEBAUTHN_H_
#include <memory>

class ChromeAuthenticatorRequestDelegate;
namespace content {
class RenderFrameHost;
class WebContents;
}
namespace parc {
// ChromeContentBrowserClient's request delegate, Chrome's scheduler call,
// with an installed page told about each request it creates.
std::unique_ptr<ChromeAuthenticatorRequestDelegate>
CreateWebAuthenticationRequestDelegate(
    content::RenderFrameHost* render_frame_host);
// Real Chrome request scheduling, credential policy, sheet models and macOS
// authorization remain authoritative. Call attached=false before view removal.
void InstallNativeWebAuthn(content::WebContents&);
void SetNativeWebAuthnAttached(content::WebContents&, bool);
}  // namespace parc
#endif
