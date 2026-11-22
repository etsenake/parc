#import "FocusManagerTestsSupport.h"

@implementation FocusManagerTestsFocusView
- (instancetype)initWithFrame:(NSRect)frame {
  self = [super initWithFrame:frame];
  if (self) {
    _acceptsFocus = YES;
  }
  return self;
}
- (BOOL)acceptsFirstResponder {
  return _acceptsFocus;
}
- (BOOL)becomeFirstResponder {
  ++_requests;
  return _acceptsFocus;
}
@end

@implementation FocusManagerTestsGateWindow
- (NSResponder*)firstResponder {
  return _reportsNilResponder ? nil : [super firstResponder];
}
- (void)simulateMissingFirstResponder {
  [self willChangeValueForKey:@"firstResponder"];
  _reportsNilResponder = YES;
  [self didChangeValueForKey:@"firstResponder"];
}
- (BOOL)makeFirstResponder:(NSResponder*)responder {
  if (responder && responder == self.blockedTarget) {
    ++_blockedRequests;
    return self.acceptWithoutChanging;
  }
  if (_reportsNilResponder) {
    [self willChangeValueForKey:@"firstResponder"];
    _reportsNilResponder = NO;
    BOOL result = [super makeFirstResponder:responder];
    [self didChangeValueForKey:@"firstResponder"];
    return result;
  }
  return [super makeFirstResponder:responder];
}
@end
