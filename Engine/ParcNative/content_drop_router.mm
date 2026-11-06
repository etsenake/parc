// Native source-owned handoff before Chromium's ordinary renderer drag route.
#import "ui/base/cocoa/content_drop_router.h"

@implementation PCNativeContentDropRouter {
  __weak NSView* _view;
  __weak NSView<PCNativeContentDropDestination>* _destination;
  __weak NSWindow* _window;
  NSPasteboard* _pasteboard;
  NSInteger _changeCount;
  NSInteger _sequence;
  BOOL _claimed;
  NSDragOperation _operation;
}
- (instancetype)initWithView:(NSView*)view {
  if ((self = [super init])) _view = view;
  return self;
}
- (BOOL)claimed { return _claimed; }
- (NSDragOperation)operation { return _operation; }
- (BOOL)valid:(id<NSDraggingInfo>)info {
  NSView* view = _view;
  NSView* destination = _destination;
  return _claimed && view && destination && _window && view.window == _window &&
         destination.window == _window && [view isDescendantOf:destination] &&
         info.draggingDestinationWindow == _window &&
         info.draggingSequenceNumber == _sequence &&
         info.draggingPasteboard == _pasteboard &&
         _pasteboard.changeCount == _changeCount;
}
- (BOOL)begin:(id<NSDraggingInfo>)info {
  [self end];
  NSView* view = _view;
  NSWindow* window = view.window;
  if (!view || !window || info.draggingDestinationWindow != window) return NO;
  for (NSView* parent = view.superview; parent; parent = parent.superview) {
    if (![parent conformsToProtocol:@protocol(PCNativeContentDropDestination)]) continue;
    NSView<PCNativeContentDropDestination>* destination = (id)parent;
    _destination = destination;
    _window = window;
    _pasteboard = info.draggingPasteboard;
    _changeCount = _pasteboard.changeCount;
    _sequence = info.draggingSequenceNumber;
    _claimed = YES;
    NSDragOperation operation = [destination contentView:view beginDrop:info];
    if (!operation) { [self end]; return NO; }
    _claimed = YES;
    if (![self valid:info]) { [self cancelRecipient]; return YES; }
    _operation = operation & info.draggingSourceOperationMask;
    return YES;
  }
  return NO;
}
- (void)cancelRecipient {
  NSView* view = _view;
  NSView<PCNativeContentDropDestination>* destination = _destination;
  _destination = nil; _operation = NSDragOperationNone;
  if (view && destination) [destination contentViewDidEndDrop:view];
}
- (NSDragOperation)update:(id<NSDraggingInfo>)info {
  if (![self valid:info]) { [self cancelRecipient]; return NSDragOperationNone; }
  NSDragOperation operation = [_destination contentView:_view updateDrop:info];
  if (![self valid:info]) { [self cancelRecipient]; return NSDragOperationNone; }
  _operation = operation & info.draggingSourceOperationMask;
  return _operation;
}
- (BOOL)prepare:(id<NSDraggingInfo>)info {
  if (![self valid:info] || !(_operation & info.draggingSourceOperationMask)) { [self cancelRecipient]; return NO; }
  BOOL ready = [_destination contentView:_view prepareDrop:info];
  if (![self valid:info]) { [self cancelRecipient]; return NO; }
  return ready;
}
- (BOOL)perform:(id<NSDraggingInfo>)info {
  BOOL result = [self prepare:info] && [_destination contentView:_view performDrop:info];
  [self end];
  return result;
}
- (void)exit:(id<NSDraggingInfo>)info {
  if (info && [self valid:info] &&
      [_destination respondsToSelector:@selector(contentView:handoffDrop:router:)]) {
    NSView<PCNativeContentDropDestination>* destination = _destination;
    if ([destination contentView:_view handoffDrop:info router:self]) {
      // A callback may synchronously retire the original owner.
      if (![self valid:info]) [self cancelRecipient];
      return;
    }
  }
  [self end];
}
- (void)end {
  NSView* view = _view;
  NSView<PCNativeContentDropDestination>* destination = _destination;
  BOOL notify = _claimed;
  _claimed = NO; _operation = NSDragOperationNone;
  _destination = nil; _window = nil; _pasteboard = nil;
  if (notify && view && destination) [destination contentViewDidEndDrop:view];
}
@end
