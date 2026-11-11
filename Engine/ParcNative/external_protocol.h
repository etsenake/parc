// Copyright 2026 Parc contributors.
#ifndef PARC_NATIVE_EXTERNAL_PROTOCOL_H_
#define PARC_NATIVE_EXTERNAL_PROTOCOL_H_
#include <optional>
#include <string>

#include "content/public/browser/weak_document_ptr.h"
#include "ui/base/page_transition_types.h"
#include "url/gurl.h"
#include "url/origin.h"
namespace content {
class WebContents;
}
namespace parc {
void InstallNativeExternalProtocol(content::WebContents&);
void SetNativeExternalProtocolAttached(content::WebContents&, bool attached);
// ExternalProtocolHandler's platform dialog for every page, after Chromium's
// policy checks: installed pages get the native sheet, any other page
// Chromium's Views dialog.
void RunExternalProtocolPrompt(
    const GURL& url,
    content::WebContents* contents,
    ui::PageTransition page_transition,
    bool has_user_gesture,
    bool is_in_fenced_frame_tree,
    const std::optional<url::Origin>& initiating_origin,
    content::WeakDocumentPtr initiator_document,
    const std::u16string& program_name);
}  // namespace parc
#endif
