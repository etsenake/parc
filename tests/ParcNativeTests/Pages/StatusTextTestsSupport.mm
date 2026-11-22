#import "StatusTextTestsSupport.h"

using namespace StatusTextTestsSupportFunctions;

@implementation StatusTextTestsStatusTheme
- (NSColor*)statusTextThemeBackgroundColor { return self.background; }
- (NSAppearance*)statusTextThemeAppearance { return self.appearance; }
@end

@implementation StatusTextTestsSupport

- (void)setUp {
  [super setUp];
  window = Window();
  page = Page(window);
}

- (void)attach {
  controller = Controller(page);
  overlay = Find(page, @"parc-status-overlay");
  pill = Find(page, @"parc-status-pill");
  label = (NSTextField*)Find(page, @"parc-status-label");
  icon = (NSImageView*)Find(page, @"parc-status-icon");
}

- (void)show:(NSString*)text {
  [self attach];
  [controller updateText:text];
  Pump(.6);
}

- (void)tearDown {
  [controller invalidate];
  ParcNativeClose(window);
  [super tearDown];
}

@end
