#import "ParcEngine.h"

#include "../Support/TestFailure.h"
#include <stdio.h>

static BOOL OldEngine;
static void (^Completion)(PCNativeImportExtensionResult*);
static void (^Background)(NSArray<PCNativeImportExtensionFailure*>*);
static NSError* RestrictionAsked;

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

@interface PCNativeImportExtensionFailure (Test)
- (instancetype)initWithIdentifier:(NSString*)identifier
                              name:(NSString*)name
                       profilePath:(NSString*)profilePath
                       restriction:(PCNativeExtensionRestriction)restriction;
@end
@implementation PCNativeImportExtensionFailure
@synthesize identifier = _identifier, name = _name, profilePath = _profilePath, restriction = _restriction;
- (instancetype)initWithIdentifier:(NSString*)identifier
                              name:(NSString*)name
                       profilePath:(NSString*)profilePath
                       restriction:(PCNativeExtensionRestriction)restriction {
  if ((self = [super init])) {
    _identifier = identifier;
    _name = name;
    _profilePath = profilePath;
    _restriction = restriction;
  }
  return self;
}
@end
@interface PCNativeImportExtensionResult (Test)
- (instancetype)initWithFailures:(NSArray*)failures;
@end
@implementation PCNativeImportExtensionResult
@synthesize failures = _failures;
- (instancetype)initWithFailures:(NSArray*)failures {
  if ((self = [super init])) {
    _failures = failures;
  }
  return self;
}
@end
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
  PARC_EXPECT(session != nil && Completion != nil && Background != nil);
}
static BOOL NameOnly(PCImportedExtensionFailure* failure, NSString* name) {
  return [failure.name isEqualToString:name] && !failure.identifier && !failure.profilePath &&
         failure.restriction == PCNativeExtensionRestrictionNone;
}

int main(void) {
  ParcExitOnUncaughtExceptions();
  @autoreleasepool {
    NSError* error = [NSError errorWithDomain:@"test" code:1 userInfo:nil];

    OldEngine = YES;
    Install();
    OldResult* old = [OldResult new];
    old.failedNames = @[ @"uBlock Origin", @"Grammarly" ];
    Completion((PCNativeImportExtensionResult*)old);
    PARC_EXPECT(Reported.count == 2 && NameOnly(Reported[0], @"uBlock Origin") &&
                NameOnly(Reported[1], @"Grammarly"));
    Background((NSArray*)@[ @"Grammarly" ]);
    PARC_EXPECT(Late.count == 1 && NameOnly(Late[0], @"Grammarly"));
    PARC_EXPECT([PCImportedExtensions restrictionForError:error] == PCNativeExtensionRestrictionNone &&
                RestrictionAsked == nil);

    OldEngine = NO;
    Install();
    PCNativeImportExtensionFailure* blocked = [[PCNativeImportExtensionFailure alloc]
        initWithIdentifier:@"grammarly"
                      name:@"Grammarly"
               profilePath:@"/profiles/Work"
               restriction:PCNativeExtensionRestrictionAdministrator];
    PCNativeImportExtensionFailure* odd = [[PCNativeImportExtensionFailure alloc]
        initWithIdentifier:@"odd"
                      name:@"Odd"
               profilePath:@"/profiles/Work"
               restriction:(PCNativeExtensionRestriction)99];
    Completion([[PCNativeImportExtensionResult alloc] initWithFailures:@[ blocked, odd ]]);
    PARC_EXPECT(Reported.count == 2 && [Reported[0].name isEqualToString:@"Grammarly"] &&
                [Reported[0].identifier isEqualToString:@"grammarly"] &&
                [Reported[0].profilePath isEqualToString:@"/profiles/Work"] &&
                Reported[0].restriction == PCNativeExtensionRestrictionAdministrator &&
                [Reported[1].identifier isEqualToString:@"odd"] &&
                Reported[1].restriction == PCNativeExtensionRestrictionNone);
    Background((NSArray*)@[ blocked, @3, [NSNull null] ]);
    PARC_EXPECT(Late.count == 1 && [Late[0].identifier isEqualToString:@"grammarly"]);
    PARC_EXPECT([PCImportedExtensions restrictionForError:error] == PCNativeExtensionRestrictionParentalApproval &&
                RestrictionAsked == error);

    Install();
    Completion((PCNativeImportExtensionResult*)[ShapelessResult new]);
    PARC_EXPECT(Reported != nil && Reported.count == 0);
  }
  printf("Imported extension reports: checks passed\n");
  return 0;
}
