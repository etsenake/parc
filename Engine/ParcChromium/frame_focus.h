// Copyright 2026 Parc contributors.
#ifndef PARC_FRAME_FOCUS_H_
#define PARC_FRAME_FOCUS_H_

#include "base/callback_list.h"

namespace content {
class WebContents;
}
namespace parc {
base::CallbackListSubscription SubscribeFrameFocus(content::WebContents&,
                                                  base::RepeatingClosure);
void NotifyFrameFocus(content::WebContents*);
}
#endif
