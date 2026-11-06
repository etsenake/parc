// Copyright 2026 Parc contributors.
#ifndef PARC_NATIVE_WEBAUTHN_H_
#define PARC_NATIVE_WEBAUTHN_H_
namespace content {
class WebContents;
}
namespace parc {
// Real Chrome request scheduling, credential policy, sheet models and macOS
// authorization remain authoritative. Call attached=false before view removal.
void InstallNativeWebAuthn(content::WebContents&);
void SetNativeWebAuthnAttached(content::WebContents&, bool);
}  // namespace parc
#endif
