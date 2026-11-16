#include "content/renderer/parc_native_link_policy.h"

#include "third_party/blink/public/web/web_document.h"
#include "third_party/blink/public/web/web_local_frame.h"
#include "third_party/blink/public/web/web_navigation_params.h"
#include "third_party/blink/public/platform/web_url_request.h"
#include "url/gurl.h"

namespace content::parc {
bool MayPrepareNativeMainFrameLink(blink::WebLocalFrame& frame,
                                   const blink::WebNavigationInfo& info,
                                   bool use_archive,
                                   const GURL& url) {
  const bool trusted =
      info.triggering_event_info == blink::mojom::TriggeringEventInfo::kFromTrustedEvent;
  const bool option = info.navigation_policy == blink::kWebNavigationPolicyDownload && trusted;
  return (frame.IsOutermostMainFrame() || option) && !use_archive &&
      info.navigation_type == blink::kWebNavigationTypeLinkClicked &&
      (info.navigation_policy == blink::kWebNavigationPolicyCurrentTab || option ||
       ((info.navigation_policy == blink::kWebNavigationPolicyNewForegroundTab ||
         info.navigation_policy == blink::kWebNavigationPolicyNewBackgroundTab) &&
        info.native_link_input_modifiers.has_value() && trusted)) &&
      info.has_transient_user_activation && !info.is_client_redirect &&
      !info.is_opener_navigation && info.form.IsNull() &&
      info.frame_load_type == blink::WebFrameLoadType::kStandard &&
      info.force_history_push == blink::mojom::ForceHistoryPush::kNo &&
      !info.is_container_initiated && !info.script_tool_invocation_id &&
      info.script_injector_host.IsEmpty() &&
      !info.resume_defer_commit_listener.is_valid() &&
      info.initiator_origin_trial_features.empty() &&
      info.should_check_main_world_content_security_policy ==
          network::mojom::CSPDisposition::CHECK &&
      (option || (!info.initiator_frame_has_download_sandbox_flag &&
                  frame.IsAllowedToDownload() && !info.initiator_frame_is_ad &&
                  !frame.IsAdFrame() && !info.is_ad_script_in_stack)) &&
      info.url_request.HasUserGesture() &&
      !info.is_history_navigation_in_new_child_frame &&
      url.SchemeIsHTTPOrHTTPS() &&
      info.initiator_frame_token == frame.GetLocalFrameToken() &&
      info.initiator_document_token == frame.GetDocument().Token();
}
}
