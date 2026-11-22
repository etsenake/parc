#import "PageHostTestsSupport.h"

@implementation PageHostTestsRendererView
- (instancetype)initWithFrame:(NSRect)frame {
  self = [super initWithFrame:frame];
  if (self) self.acceptsFocus = YES;
  return self;
}
- (BOOL)acceptsFirstResponder { return self.acceptsFocus; }
- (BOOL)becomeFirstResponder {
  self.focusRequests += 1;
  return self.acceptsFocus;
}
@end

@implementation PageHostTestsHostObserver
- (instancetype)init {
  self = [super init];
  if (self) self.moves = [NSMutableArray array];
  return self;
}
- (void)pageHost:(PCNativePageHost *)host didMoveToWindow:(NSWindow *)window {
  Check(host.window == window, "observer gets the actual current host window");
  self.lastWindow = window;
  [self.moves addObject:window ? @"attach" : @"detach"];
}
- (void)pageHostDidAttemptDeferredFocus:(PCNativePageHost *)host {
  (void)host;
  self.focusAttempts += 1;
}
@end

@implementation PageHostTestsReentrantView
- (void)viewDidMoveToWindow {
  [super viewDidMoveToWindow];
  if (self.window && self.didAttach) self.didAttach();
}
@end

@implementation PageHostTestsVisibilityView
- (void)setHidden:(BOOL)hidden {
  [super setHidden:hidden];
  ++_hiddenChanges;
  void (^callback)(void) = self.visibilityChanged;
  if (callback) callback();
}
@end

@implementation PageHostTestsLayoutView
- (void)layoutSubtreeIfNeeded {
  ++_subtreeLayouts;
  [super layoutSubtreeIfNeeded];
}
- (void)layout {
  [super layout];
  if (self.didLayout) self.didLayout();
}
@end
