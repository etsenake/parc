// Copyright 2026 Parc contributors.
#ifndef PARC_NATIVE_NATIVE_PAGE_INFO_H_
#define PARC_NATIVE_NATIVE_PAGE_INFO_H_
#include "components/content_settings/core/common/content_settings_types.h"
namespace content { class WebContents; }
namespace parc {
// Native counterpart of the captured-surface-control delegate's PageInfo call.
// No synthetic response: the real PageInfo permission model owns all changes.
bool ShowNativePageInfoPermission(content::WebContents* contents, ContentSettingsType type);
}  // namespace parc
#endif
