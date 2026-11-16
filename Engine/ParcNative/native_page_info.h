// Copyright 2026 Parc contributors.
#ifndef PARC_NATIVE_NATIVE_PAGE_INFO_H_
#define PARC_NATIVE_NATIVE_PAGE_INFO_H_
#include "components/content_settings/core/common/content_settings_types.h"
namespace content { class WebContents; }
namespace parc {
bool ShowNativePageInfoPermission(content::WebContents* contents, ContentSettingsType type);
void RefreshNativeSiteControls(content::WebContents* contents);
}
#endif
