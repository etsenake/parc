// Copyright 2026 Parc contributors.
#ifndef PARC_NATIVE_EXTERNAL_PROTOCOL_H_
#define PARC_NATIVE_EXTERNAL_PROTOCOL_H_
namespace content {
class WebContents;
}
namespace parc {
void InstallNativeExternalProtocol(content::WebContents&);
void SetNativeExternalProtocolAttached(content::WebContents&, bool attached);
}  // namespace parc
#endif
