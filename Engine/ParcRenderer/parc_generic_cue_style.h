#ifndef THIRD_PARTY_BLINK_RENDERER_CORE_HTML_MEDIA_PARC_GENERIC_CUE_STYLE_H_
#define THIRD_PARTY_BLINK_RENDERER_CORE_HTML_MEDIA_PARC_GENERIC_CUE_STYLE_H_

#include <optional>

#include "third_party/blink/renderer/core/html/track/vtt/vtt_cue.h"

namespace blink {

class VTTCueBox;

void ApplyParcGenericCueStyle(
    const std::optional<VTTCue::ParcGenericCueStyle>& generic_style,
    VTTCueBackgroundBox* background_box,
    VTTCueBox* display_tree);

}

#endif
