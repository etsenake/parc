// Copyright 2026 Parc contributors.
// Parc presents Safari's identity to the sites that need Apple FairPlay
// (docs/fairplay-identity.md). A page's documents get it through the
// WebContents user agent override, but service and shared workers start
// outside any WebContents with the browser-wide user agent. This hook lets
// the embedder give such a worker its site's identity, so its
// navigator.userAgent and its fetches match the documents of that site.
// Installed at content/public/browser/parc_worker_identity.h.
#ifndef CONTENT_PUBLIC_BROWSER_PARC_WORKER_IDENTITY_H_
#define CONTENT_PUBLIC_BROWSER_PARC_WORKER_IDENTITY_H_

#include <string>

#include "content/common/content_export.h"

class GURL;

namespace blink {
struct UserAgentMetadata;
}

namespace content {

class BrowserContext;

// Called on the UI thread as a worker starts, with its script URL and the
// top-level site of its storage partition, after content filled in the
// browser-wide user agent and metadata. The hook may replace both.
using ParcWorkerIdentityHook = void (*)(BrowserContext* browser_context,
                                        const GURL& script_url,
                                        const GURL& top_level_site,
                                        std::string* user_agent,
                                        blink::UserAgentMetadata* metadata);

// Installs the embedder's hook; nullptr removes it. Call on the main
// thread before the browser starts.
CONTENT_EXPORT void SetParcWorkerIdentityHook(ParcWorkerIdentityHook hook);

// Runs the installed hook, if any. Content-internal; defined in
// content/browser/service_worker/service_worker_version.cc.
void ApplyParcWorkerIdentity(BrowserContext* browser_context,
                             const GURL& script_url,
                             const GURL& top_level_site,
                             std::string* user_agent,
                             blink::UserAgentMetadata* metadata);

}  // namespace content

#endif  // CONTENT_PUBLIC_BROWSER_PARC_WORKER_IDENTITY_H_
