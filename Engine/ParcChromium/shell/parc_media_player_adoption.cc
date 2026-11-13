// Copyright 2013 The Chromium Authors

#include <utility>

#include "content/renderer/render_frame_impl.h"

namespace content {

bool RenderFrameImpl::ParcAdoptMediaPlayer(
    blink::WebMediaPlayer& player,
    const blink::WebString& sink_id,
    blink::MediaInspectorContext* inspector_context) {
  return media_factory_.ParcAdoptMediaPlayer(player, sink_id,
                                             inspector_context);
}

}
