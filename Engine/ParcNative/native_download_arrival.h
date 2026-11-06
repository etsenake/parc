// Copyright 2026 Parc contributors.
#ifndef PARC_NATIVE_NATIVE_DOWNLOAD_ARRIVAL_H_
#define PARC_NATIVE_NATIVE_DOWNLOAD_ARRIVAL_H_
#include "downloads.h"
#import "native_appkit_bridge.h"
class Profile;
namespace parc {
// Genuine creation only. The manager has already unwound its observer stack.
// No profile/page is created, no URL is replayed, and history never calls this.
// Delivers -nativeBrowser:downloadDidBegin: to the original window's client.
void PresentNativeDownloadArrival(Profile&, NativeDownloadSnapshot,
                                  content::WeakDocumentPtr, NSString* context_id);
}  // namespace parc
#endif
