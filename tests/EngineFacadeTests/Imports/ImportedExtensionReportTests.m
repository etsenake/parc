#import "ImportEngineStub.h"

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
@interface ImportedExtensionReportTests : ParcNativeTestCase
@end

@implementation ImportedExtensionReportTests

- (void)setUp {
  [super setUp];
  OldEngine = NO;
  RestrictionAsked = nil;
}

- (void)testFailuresCarryIdentityProfileAndKnownRestriction {
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
  PARC_CHECK(Reported.count == 2 && [Reported[0].name isEqualToString:@"Grammarly"] &&
             [Reported[0].identifier isEqualToString:@"grammarly"] &&
             [Reported[0].profilePath isEqualToString:@"/profiles/Work"] &&
             Reported[0].restriction == PCNativeExtensionRestrictionAdministrator &&
             [Reported[1].identifier isEqualToString:@"odd"] &&
             Reported[1].restriction == PCNativeExtensionRestrictionNone);
  Background((NSArray*)@[ blocked, @3, [NSNull null] ]);
  PARC_CHECK(Late.count == 1 && [Late[0].identifier isEqualToString:@"grammarly"]);
}

- (void)testRestrictionComesFromTheEngine {
  NSError* error = [NSError errorWithDomain:@"test" code:1 userInfo:nil];
  PARC_CHECK([PCImportedExtensions restrictionForError:error] == PCNativeExtensionRestrictionParentalApproval &&
             RestrictionAsked == error);
}

- (void)testAResultWithoutFailuresReportsNone {
  Install();
  Completion((PCNativeImportExtensionResult*)[ShapelessResult new]);
  PARC_CHECK(Reported != nil && Reported.count == 0);
}

@end
