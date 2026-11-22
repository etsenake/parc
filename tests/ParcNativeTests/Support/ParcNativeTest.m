#import "ParcNativeTest.h"
#import "ParcNativeWindows.h"
#import "ParcNativeClock.h"

#import <objc/runtime.h>

static ParcNativeTestCase* currentTest;

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

ParcNativeTestPresentation* ParcNativePresentation(void) {
  NSCAssert(currentTest, @"Offscreen presentation belongs to a running test");
  return currentTest.presentation;
}

ParcNativeTestScheduler* ParcNativeScheduler(void) {
  NSCAssert(currentTest, @"The test scheduler belongs to a running test");
  return currentTest.scheduler;
}

@implementation ParcNativeTestCase {
  ParcNativeTestPresentation* _presentation;
  ParcNativeTestScheduler* _scheduler;
}

- (ParcNativeTestPresentation*)presentation {
  return _presentation;
}

- (ParcNativeTestScheduler*)scheduler {
  return _scheduler;
}

+ (Class)presentationClass {
  return ParcNativeTestPresentation.class;
}

- (void)setUp {
  [super setUp];
  self.continueAfterFailure = NO;
  _presentation = [[self.class presentationClass] new];
  _scheduler = [ParcNativeTestScheduler new];
  currentTest = self;
  [NSApplication sharedApplication];
  [NSApp setActivationPolicy:NSApplicationActivationPolicyProhibited];
}

- (void)tearDown {
  BOOL onScreen = NO;
  for (NSWindow* window in NSApp.windows) onScreen |= window.visible;
  for (Class cls = self.class; cls != ParcNativeTestCase.class; cls = class_getSuperclass(cls)) {
    unsigned count = 0;
    Ivar* ivars = class_copyIvarList(cls, &count);
    for (unsigned i = 0; i < count; ++i) {
      const char* type = ivar_getTypeEncoding(ivars[i]);
      if (type && type[0] == '@') object_setIvar(self, ivars[i], nil);
    }
    free(ivars);
  }
  [_scheduler invalidate];
  XCTestCase* test = currentTest;
  currentTest = nil;
  _scheduler = nil;
  _presentation = nil;
  [super tearDown];
  if (onScreen) {
    [test recordIssue:[[XCTIssue alloc] initWithType:XCTIssueTypeAssertionFailure
                                  compactDescription:@"a window was ordered on screen"]];
  }
}

@end
