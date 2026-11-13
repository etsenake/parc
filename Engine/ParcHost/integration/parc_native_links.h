// Copyright 2026 Parc contributors.
#ifndef CONTENT_PUBLIC_BROWSER_PARC_NATIVE_LINKS_H_
#define CONTENT_PUBLIC_BROWSER_PARC_NATIVE_LINKS_H_

#include "content/common/content_export.h"

namespace content {

class WeakDocumentPtr;
class WebContents;
struct OpenURLParams;

CONTENT_EXPORT void NotifyNativeDeferredOpenURL(
    WebContents* source,
    WebContents* created,
    const WeakDocumentPtr& source_document,
    const OpenURLParams& params);

}

#endif
