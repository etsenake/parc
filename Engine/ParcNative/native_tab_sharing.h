// Copyright 2026 Parc contributors.
#ifndef PARC_NATIVE_NATIVE_TAB_SHARING_H_
#define PARC_NATIVE_NATIVE_TAB_SHARING_H_
namespace infobars { class InfoBar; }
namespace parc {
bool IsNativeTabSharingInfoBar(infobars::InfoBar* bar);
// The real delegate's Share This Tab Instead button, offered and enabled.
bool NativeTabSharingCanShareInstead(infobars::InfoBar* bar);
// Runs that genuine action (with its histogram) when it is still offered.
bool ShareNativeTabInstead(infobars::InfoBar* bar);
}  // namespace parc
#endif
