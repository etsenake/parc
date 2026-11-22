#import "ExtensionInstallTestsSupport.h"

using namespace ExtensionInstallTestsSupportFunctions;

@implementation ExtensionInstallTestsSupport

- (void)setUp {
  [super setUp];
  _w = Window();
  _choice = PCExtensionInstallInterrupted;
  _input = YES;
}

- (void)tearDown {
  ParcNativeClose(_w);
  Pump();
  [super tearDown];
}

- (void (^)(PCExtensionInstallChoice, BOOL))result {
  int* results = &_results;
  PCExtensionInstallChoice* choice = &_choice;
  BOOL* grants = &_grants;
  return ^(PCExtensionInstallChoice c, BOOL g) {
    ++*results;
    *choice = c;
    *grants = g;
  };
}

- (BOOL (^)(NSWindow*))inputAllowed {
  BOOL* input = &_input;
  return ^BOOL(NSWindow*) {
    return *input;
  };
}

- (PCExtensionInstallPresenter*)makeValidating:(BOOL (^)(void))valid {
  return Make(_w, valid, self.inputAllowed, self.result);
}

- (PCExtensionInstallPresenter*)make {
  return [self makeValidating:^BOOL {
    return YES;
  }];
}

- (PCExtensionInstallPresenter*)shownPresenter {
  PCExtensionInstallPresenter* p = [self make];
  [p start];
  Pump();
  return p;
}

- (PCExtensionInstallPresenter*)upstreamPresenterWithPermissions:(NSArray*)permissions details:(NSArray*)details {
  PCExtensionInstallPresenter* presenter = [[PCExtensionInstallPresenter alloc] initWithWindow:_w
                                                       title:@"Upstream install"
                                                        icon:nil
                                                     heading:@"Upstream permissions"
                                                 permissions:permissions
                                                     details:details
                                                 acceptLabel:@"Add"
                                                 cancelLabel:@"Cancel"
                                               checkboxLabel:nil
                                                    validate:^BOOL {
                                                      return YES;
                                                    }
                                                inputAllowed:self.inputAllowed
                                                      result:self.result];
  presenter.presentation = ParcNativePresentation();
  presenter.scheduler = ParcNativeScheduler();
  return presenter;
}

@end
