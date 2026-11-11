// Copyright 2026 Parc contributors.
#ifndef PARC_PARC_BUNDLE_MAC_H_
#define PARC_PARC_BUNDLE_MAC_H_

#include <string_view>

#include "base/files/file_path.h"

namespace parc {
// Points base's framework, outer-bundle and base-bundle-ID lookups and
// content's CHILD_PROCESS_EXE at the layout this framework was loaded from:
// <App>.app/Contents/Frameworks/<Framework>.framework/Versions/A/<binary>.
// Every process calls it once, before ContentMain. Returns false when the
// framework isn't inside an application bundle.
bool InstallBundleOverrides();
// <App>.app/Contents/Frameworks/<Exe> Helper<suffix>.app/Contents/MacOS/...,
// where <Exe> is the outer application's executable name.
base::FilePath HelperExecutablePath(std::string_view suffix);
}  // namespace parc

#endif  // PARC_PARC_BUNDLE_MAC_H_
