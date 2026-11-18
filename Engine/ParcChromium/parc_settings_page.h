#ifndef PARC_PARC_SETTINGS_PAGE_H_
#define PARC_PARC_SETTINGS_PAGE_H_

#include "base/values.h"

namespace parc {

base::DictValue SettingsPageValues();
void ReportNoBrandCode();
void RegisterSettingsWebUI();

}  // namespace parc

#endif  // PARC_PARC_SETTINGS_PAGE_H_
