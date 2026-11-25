#pragma once

#import "ParcEngine.h"
#import "ParcNativeTest.h"

static BOOL OldEngine;
static void (^Completion)(PCNativeImportExtensionResult*);
static void (^Background)(NSArray<PCNativeImportExtensionFailure*>*);
static NSError* RestrictionAsked;
static NSData* SidebarPlaintext;
static NSError* SidebarFailure;
static NSURL* SidebarAsked;
static PCNativeImportSidebarFormat SidebarFormatAsked;

@interface PCNativeImportProfile (Test)
- (instancetype)initForTest;
@end
@implementation PCNativeImportProfile
- (instancetype)initForTest { return [super init]; }
- (BOOL)respondsToSelector:(SEL)selector {
  if (OldEngine && (selector == @selector(canDecryptSidebarFiles) ||
                    selector == @selector(decryptSidebarFile:format:error:))) {
    return NO;
  }
  return [super respondsToSelector:selector];
}
- (BOOL)canDecryptSidebarFiles { return YES; }
- (NSData*)decryptSidebarFile:(NSURL*)file format:(PCNativeImportSidebarFormat)format error:(NSError**)error {
  SidebarAsked = file;
  SidebarFormatAsked = format;
  if (!SidebarPlaintext && error) {
    *error = SidebarFailure;
  }
  return SidebarPlaintext;
}
@end

@implementation PCNativePage
@end
@implementation PCNativeBrowserWindow
@end
@interface PCNativeImportSession (Test)
- (instancetype)initForTest;
@end
@implementation PCNativeImportSession
- (instancetype)initForTest { return [super init]; }
@end
@implementation PCNativeBrowserApplication
+ (BOOL)respondsToSelector:(SEL)selector {
  if (OldEngine && selector == @selector(extensionRestrictionForError:)) {
    return NO;
  }
  return [super respondsToSelector:selector];
}
+ (PCNativeImportSession*)installImportedExtensions:(NSArray<PCNativeImportExtensionRequest*>*)requests
                                         completion:(void (^)(PCNativeImportExtensionResult*))completion
                                 backgroundFailures:(void (^)(NSArray<PCNativeImportExtensionFailure*>*))backgroundFailures {
  Completion = completion;
  Background = backgroundFailures;
  return [[PCNativeImportSession alloc] initForTest];
}
+ (PCNativeExtensionRestriction)extensionRestrictionForError:(NSError*)error {
  RestrictionAsked = error;
  return PCNativeExtensionRestrictionParentalApproval;
}
@end
int parc_engine_initialize(int argc, char** argv, const char* a, const char* b, const char* c,
                           const char* d, int* e) { return 0; }
void parc_engine_run_message_loop(void) {}
int parc_engine_request_quit_when_idle(void (*ready)(void*), void* context) { return 0; }
int parc_engine_shutdown_if_idle(void) { return 0; }

@interface OldResult : NSObject
@property(nonatomic, copy) NSArray<NSString*>* failedNames;
@end
@implementation OldResult
@end
@interface ShapelessResult : NSObject
@end
@implementation ShapelessResult
@end

static NSArray<PCImportedExtensionFailure*>* Reported;
static NSArray<PCImportedExtensionFailure*>* Late;

static void Install(void) {
  Reported = nil;
  Late = nil;
  PCNativeImportSession* session = [PCImportedExtensions install:@[]
      completion:^(PCNativeImportExtensionResult* result, NSArray<PCImportedExtensionFailure*>* failures) {
        Reported = failures;
      }
      backgroundFailures:^(NSArray<PCImportedExtensionFailure*>* failures) {
        Late = failures;
      }];
  PARC_CHECK(session != nil && Completion != nil && Background != nil);
}
