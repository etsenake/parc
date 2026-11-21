#import "ParcNativeTest.h"

#import <objc/runtime.h>

static XCTestCase* currentTest;

void ParcNativeCheck(BOOL passed, const char* expression, const char* file, int line) {
  if (passed) return;
  XCTSourceCodeLocation* location = [[XCTSourceCodeLocation alloc] initWithFilePath:@(file) lineNumber:line];
  XCTIssue* issue = [[XCTIssue alloc] initWithType:XCTIssueTypeAssertionFailure
                                compactDescription:@(expression)
                               detailedDescription:nil
                                 sourceCodeContext:[[XCTSourceCodeContext alloc] initWithLocation:location]
                                   associatedError:nil
                                       attachments:@[]];
  if (currentTest) {
    [currentTest recordIssue:issue];
  } else {
    [NSException raise:NSInternalInconsistencyException format:@"%s:%d: %s", file, line, expression];
  }
}

void ParcNativeCheckMessage(const char* file, int line, bool passed, const char* message) {
  ParcNativeCheck(passed ? YES : NO, message, file, line);
}

@implementation ParcNativeTestCase

+ (NSApplicationActivationPolicy)activationPolicy {
  return NSApplicationActivationPolicyProhibited;
}

- (void)setUp {
  [super setUp];
  self.continueAfterFailure = NO;
  currentTest = self;
  [NSApplication sharedApplication];
  [NSApp setActivationPolicy:[self.class activationPolicy]];
}

- (void)tearDown {
  for (Class cls = self.class; cls != ParcNativeTestCase.class; cls = class_getSuperclass(cls)) {
    unsigned count = 0;
    Ivar* ivars = class_copyIvarList(cls, &count);
    for (unsigned i = 0; i < count; ++i) {
      const char* type = ivar_getTypeEncoding(ivars[i]);
      if (type && type[0] == '@') object_setIvar(self, ivars[i], nil);
    }
    free(ivars);
  }
  currentTest = nil;
  [super tearDown];
}

@end
