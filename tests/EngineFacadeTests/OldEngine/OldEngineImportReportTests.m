#import "ImportEngineStub.h"

static BOOL NameOnly(PCImportedExtensionFailure* failure, NSString* name) {
  return [failure.name isEqualToString:name] && !failure.identifier && !failure.profilePath &&
         failure.restriction == PCNativeExtensionRestrictionNone;
}

@interface OldEngineImportReportTests : ParcNativeTestCase
@end

@implementation OldEngineImportReportTests

- (void)setUp {
  [super setUp];
  OldEngine = YES;
  RestrictionAsked = nil;
}

- (void)testNamesOnlyResultsReportEachName {
  Install();
  OldResult* old = [OldResult new];
  old.failedNames = @[ @"uBlock Origin", @"Grammarly" ];
  Completion((PCNativeImportExtensionResult*)old);
  PARC_CHECK(Reported.count == 2 && NameOnly(Reported[0], @"uBlock Origin") &&
             NameOnly(Reported[1], @"Grammarly"));
  Background((NSArray*)@[ @"Grammarly" ]);
  PARC_CHECK(Late.count == 1 && NameOnly(Late[0], @"Grammarly"));
}

- (void)testRestrictionIsNoneWithoutEngineSupport {
  NSError* error = [NSError errorWithDomain:@"test" code:1 userInfo:nil];
  PARC_CHECK([PCImportedExtensions restrictionForError:error] == PCNativeExtensionRestrictionNone &&
             RestrictionAsked == nil);
}

@end
