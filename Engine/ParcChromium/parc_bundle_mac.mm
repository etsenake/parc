// Copyright 2026 Parc contributors.
// Portions copyright 2012 The Chromium Authors and The Chromium Embedded
// Framework Authors (chrome/app/chrome_main_mac.mm, cef/libcef/common/util_mac.mm).
#include "parc/parc_bundle_mac.h"

#import <Foundation/Foundation.h>
#include <dlfcn.h>

#include <string>

#include "base/apple/bundle_locations.h"
#include "base/apple/foundation_util.h"
#include "base/files/file_util.h"
#include "base/path_service.h"
#include "base/strings/sys_string_conversions.h"
#include "content/public/common/content_paths.h"

namespace parc {
namespace {
// The framework is the image containing this function, wherever the app
// bundle was moved; the working directory and argv[0] play no part.
base::FilePath LoadedFrameworkPath() {
  Dl_info info;
  if (!dladdr(reinterpret_cast<const void*>(&LoadedFrameworkPath), &info) ||
      !info.dli_fname) {
    return base::FilePath();
  }
  // dyld reports the path it was given, here the top-level symlink
  // <Framework>.framework/<binary>; resolve to the versioned binary first.
  for (base::FilePath path =
           base::MakeAbsoluteFilePath(base::FilePath(info.dli_fname));
       !path.empty() && path != path.DirName(); path = path.DirName()) {
    if (path.Extension() == ".framework") {
      return path;
    }
  }
  return base::FilePath();
}
}  // namespace

bool InstallBundleOverrides() {
  @autoreleasepool {
    const base::FilePath framework = LoadedFrameworkPath();
    if (framework.empty()) {
      return false;
    }
    // <App>.app/Contents/Frameworks/<Framework>.framework
    const base::FilePath outer = framework.DirName().DirName().DirName();
    NSBundle* outer_bundle =
        [NSBundle bundleWithPath:base::apple::FilePathToNSString(outer)];
    if (outer.Extension() != ".app" || !outer_bundle.bundleIdentifier ||
        !outer_bundle.executablePath) {
      return false;
    }
    base::apple::SetOverrideFrameworkBundlePath(framework);
    base::apple::SetOverrideOuterBundlePath(outer);
    base::apple::SetBaseBundleIDOverride(
        base::SysNSStringToUTF8(outer_bundle.bundleIdentifier));
    // Content picks the Renderer and GPU variants from this default helper.
    return base::PathService::OverrideAndCreateIfNeeded(
        content::CHILD_PROCESS_EXE, HelperExecutablePath(""),
        /*is_absolute=*/true, /*create=*/false);
  }
}

base::FilePath HelperExecutablePath(std::string_view suffix) {
  @autoreleasepool {
    const std::string name =
        base::SysNSStringToUTF8(
            base::apple::OuterBundle().executablePath.lastPathComponent) +
        " Helper" + std::string(suffix);
    return base::apple::FrameworkBundlePath()
        .DirName()
        .Append(name + ".app")
        .Append("Contents")
        .Append("MacOS")
        .Append(name);
  }
}
}  // namespace parc
