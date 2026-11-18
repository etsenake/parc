#ifndef PARC_PARC_SETTINGS_PAGE_H_
#define PARC_PARC_SETTINGS_PAGE_H_

#include "base/files/file_path.h"
#include "base/values.h"

namespace parc {

base::DictValue SettingsPageValues();
void ReportNoBrandCode();
void UseParcRlzStore(const base::FilePath& user_data_dir);
void RegisterSettingsWebUI();

}  // namespace parc

#endif  // PARC_PARC_SETTINGS_PAGE_H_
