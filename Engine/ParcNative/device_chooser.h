// Copyright 2026 Parc contributors.
#ifndef PARC_NATIVE_DEVICE_CHOOSER_H_
#define PARC_NATIVE_DEVICE_CHOOSER_H_

#include <memory>

#include "base/functional/callback.h"

namespace content {
class RenderFrameHost;
}
namespace permissions {
class ChooserController;
}
namespace parc {
base::OnceClosure ShowNativeDeviceChooser(
    content::RenderFrameHost* frame,
    std::unique_ptr<permissions::ChooserController> controller);
}

#endif
