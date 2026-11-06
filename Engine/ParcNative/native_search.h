// Copyright 2026 Parc contributors.
#ifndef PARC_NATIVE_NATIVE_SEARCH_H_
#define PARC_NATIVE_NATIVE_SEARCH_H_
#import "native_appkit_bridge.h"
class Profile;
class CefPreferenceRegistrar;
namespace parc {
void RegisterNativeSearchPreferences(CefPreferenceRegistrar& registrar);
void InitializeNativeSearch(Profile& profile);
Profile* ProfileForSearchNavigation(PCNativeSearchNavigation* request);
}
@interface PCNativeBrowserWindow (SearchCreation)
- (void)openURL:(NSURL*)url
         profilePath:(NSString*)path
           container:(NSView*)container
    searchNavigation:(PCNativeSearchNavigation*)request
          completion:(void (^)(PCNativePage*, NSError*))completion;
- (void)openBackgroundURL:(NSURL*)url
    profilePath:(NSString*)path container:(NSView*)container
    searchNavigation:(PCNativeSearchNavigation*)search
    validateOwner:(BOOL (^)(void))validateOwner
    completion:(void (^)(PCNativePage*, NSError*))completion;
@end
#endif
