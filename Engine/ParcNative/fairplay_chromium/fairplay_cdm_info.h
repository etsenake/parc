// FairPlay Streaming's registration, made by Parc's content clients: the
// browser's CdmRegistry entry and the renderer's key system, from one
// capability. The CDM and its renderer run in the GPU process's media service.
#ifndef THIRD_PARTY_PARC_FAIRPLAY_CHROMIUM_FAIRPLAY_CDM_INFO_H_
#define THIRD_PARTY_PARC_FAIRPLAY_CHROMIUM_FAIRPLAY_CDM_INFO_H_

#include <memory>

#include "content/public/common/cdm_info.h"
#include "media/base/key_system_info.h"

namespace parc::fairplay {

content::CdmInfo GetFairPlayCdmInfo();

// Safari's persistent-usage-record sessions are offered only where the render
// process can persist data, as Safari keeps none in a private window.
std::unique_ptr<media::KeySystemInfo> CreateFairPlayKeySystemInfo(
    bool can_persist_data);

}  // namespace parc::fairplay

#endif  // THIRD_PARTY_PARC_FAIRPLAY_CHROMIUM_FAIRPLAY_CDM_INFO_H_
