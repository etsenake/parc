// Copyright 2026 Parc contributors.
#ifndef PARC_NATIVE_NATIVE_PAGE_RETIREMENT_H_
#define PARC_NATIVE_NATIVE_PAGE_RETIREMENT_H_
#import "native_appkit_bridge.h"
namespace parc {
bool HasNativePageRetirementWork();
bool IsNativePageRetiring(PCNativePage* page);
}  // namespace parc
#endif
