// Copyright 2026 Parc contributors.
#ifndef PARC_WEBUI_BRANDING_H_
#define PARC_WEBUI_BRANDING_H_

#include <string_view>

#include "base/memory/scoped_refptr.h"
#include "ui/base/resource/resource_scale_factor.h"

namespace base {
class RefCountedMemory;
}
namespace gfx {
class Image;
}

namespace parc {

scoped_refptr<base::RefCountedMemory> LoadBrandedResource(
    int resource_id,
    ui::ResourceScaleFactor scale_factor);
bool GetBrandedImageBytes(int resource_id,
                          ui::ResourceScaleFactor scale_factor,
                          std::string_view* value);
gfx::Image GetBrandedImage(int resource_id);

}

#endif
