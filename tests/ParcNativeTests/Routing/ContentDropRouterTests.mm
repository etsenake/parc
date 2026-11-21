#import "content_drop_router.h"
#import "ParcNativeTest.h"
#include <cstdio>
#include <cstdlib>
@interface DragFixture : NSObject
@property NSWindow* draggingDestinationWindow;
@property NSPasteboard* draggingPasteboard;
@property NSInteger draggingSequenceNumber;
@property NSDragOperation draggingSourceOperationMask;
@end
@implementation DragFixture
@end
@interface DropFixture : NSView<PCNativeContentDropDestination>
@property int begins, updates, prepares, performs, ends;
@property BOOL accepts, ready, succeeds, handoff, detachOnHandoff;
@property id<PCNativeContentDropRouting> continuation;
@end
@implementation DropFixture
- (NSDragOperation)contentView:(NSView*)view beginDrop:(id<NSDraggingInfo>)info { self.begins++; return self.accepts ? NSDragOperationCopy : NSDragOperationNone; }
- (NSDragOperation)contentView:(NSView*)view updateDrop:(id<NSDraggingInfo>)info { self.updates++; return self.accepts ? NSDragOperationCopy : NSDragOperationNone; }
- (BOOL)contentView:(NSView*)view prepareDrop:(id<NSDraggingInfo>)info { self.prepares++; return self.ready; }
- (BOOL)contentView:(NSView*)view performDrop:(id<NSDraggingInfo>)info { self.performs++; return self.succeeds; }
- (void)contentViewDidEndDrop:(NSView*)view { self.ends++; self.continuation=nil; }
- (BOOL)contentView:(NSView*)view handoffDrop:(id<NSDraggingInfo>)info router:(id<PCNativeContentDropRouting>)router {
  if (!self.handoff) return NO;
  self.continuation=router;
  if (self.detachOnHandoff) [view removeFromSuperview];
  return YES;
}
@end
#define Check(...) ParcNativeCheckMessage(__FILE__, __LINE__, __VA_ARGS__)
@interface ParcNativeTests_ContentDropRouterTests : ParcNativeTestCase
@end

@implementation ParcNativeTests_ContentDropRouterTests {
  NSWindow* _window;
  DropFixture* _owner;
  NSView* _view;
  DragFixture* _drag;
  id<NSDraggingInfo> _info;
  PCNativeContentDropRouter* _router;
}

- (void)setUp {
  [super setUp];
  _window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 200, 200)
                                        styleMask:NSWindowStyleMaskBorderless
                                          backing:NSBackingStoreBuffered
                                            defer:NO];
  _owner = [[DropFixture alloc] initWithFrame:NSMakeRect(0, 0, 200, 200)];
  _window.contentView = _owner;
  _view = [[NSView alloc] initWithFrame:_owner.bounds];
  [_owner addSubview:_view];
  _drag = [DragFixture new];
  _drag.draggingDestinationWindow = _window;
  _drag.draggingPasteboard = [NSPasteboard pasteboardWithUniqueName];
  _drag.draggingSequenceNumber = 7;
  _drag.draggingSourceOperationMask = NSDragOperationCopy;
  [_drag.draggingPasteboard setString:@"https://fixture.invalid" forType:NSPasteboardTypeURL];
  _info = (id)_drag;
  _router = [[PCNativeContentDropRouter alloc] initWithView:_view];
}

- (void)tearDown {
  [_drag.draggingPasteboard releaseGlobally];
  [super tearDown];
}

- (void)accept {
  _owner.accepts = YES;
  _owner.ready = YES;
  _owner.succeeds = YES;
}

- (void)testDeclinedInputStaysWithChromium {
  Check(![_router begin:_info] && !_router.claimed, "declined input remains Chromium owned");
}

- (void)testAnAcceptedGestureUpdatesAndCommitsOnce {
  [self accept];
  Check([_router begin:_info] && _router.claimed && _router.operation == NSDragOperationCopy,
        "claim original native gesture");
  Check([_router update:_info] == NSDragOperationCopy && _owner.updates == 1, "update actual receiver");
  Check([_router prepare:_info] && [_router perform:_info] && _owner.performs == 1 && !_router.claimed,
        "single native commit and cleanup");
  Check(![_router perform:_info] && _owner.performs == 1, "no repeated commit");
}

- (void)testAnExpiredPasteboardCancelsWithoutCommitting {
  [self accept];
  [_router begin:_info];
  const int ends = _owner.ends;
  [_drag.draggingPasteboard clearContents];
  Check([_router update:_info] == NSDragOperationNone && _router.claimed,
        "expired pasteboard never falls through to renderer");
  Check(_owner.ends == ends + 1 && ![_router perform:_info] && _owner.performs == 0,
        "expired payload cancels original preview without commit");
}

- (void)testADifferentGestureInvalidatesTheLease {
  [self accept];
  [_router begin:_info];
  const int ends = _owner.ends;
  _drag.draggingSequenceNumber++;
  Check(![_router prepare:_info] && _router.claimed && _owner.ends == ends + 1,
        "different gesture invalidates original lease");
  [_router end];
}

- (void)testReparentingCancelsTheRecipient {
  [self accept];
  [_router begin:_info];
  [_view removeFromSuperview];
  const int ends = _owner.ends;
  Check([_router update:_info] == NSDragOperationNone && _owner.ends == ends + 1, "reparent cancels recipient");
  Check(_router.claimed && ![_router perform:_info], "reparent cannot resume webpage fallback or drop");
}

- (void)testAPrepareRefusalReportsFailure {
  [self accept];
  [_router begin:_info];
  _owner.ready = NO;
  Check(![_router perform:_info] && _owner.performs == 0 && !_router.claimed, "prepare refusal reports failure");
}

- (void)testACommitFailureIsReported {
  [self accept];
  _owner.succeeds = NO;
  [_router begin:_info];
  Check(![_router perform:_info] && _owner.performs == 1 && !_router.claimed, "real commit failure preserved");
}

- (void)testTheSourceOperationMaskIsHonoured {
  [self accept];
  _drag.draggingSourceOperationMask = NSDragOperationMove;
  [_router begin:_info];
  Check(_router.operation == NSDragOperationNone && [_router update:_info] == NSDragOperationNone,
        "honor source operation mask");
  Check(![_router prepare:_info] && ![_router perform:_info], "incompatible operation cannot commit");
  [_router end];
}

- (void)testAnAcceptedHandoffContinuesOnlyTheOriginalLease {
  [self accept];
  _owner.handoff = YES;
  [_router begin:_info];
  const int ends = _owner.ends;
  [_router exit:_info];
  Check(_router.claimed && _owner.continuation == _router && _owner.ends == ends,
        "exit retains only same accepted native router");
  Check([_owner.continuation update:_info] == NSDragOperationCopy, "ancestor continuation uses original lease");
  _drag.draggingSequenceNumber++;
  Check(![_owner.continuation prepare:_info] && _owner.ends == ends + 1 && !_owner.continuation,
        "handoff cannot accept another native sequence");
}

- (void)testTheOriginalEndRetiresTheContinuation {
  [self accept];
  _owner.handoff = YES;
  [_router begin:_info];
  [_router exit:_info];
  const int ends = _owner.ends;
  [_router end];
  Check(_owner.ends == ends + 1 && !_owner.continuation && !_router.claimed,
        "original terminal callback retires ancestor continuation");
}

- (void)testLosingTheOwnerDuringHandoffCancelsWithoutFallback {
  [self accept];
  _owner.handoff = YES;
  [_router begin:_info];
  _owner.detachOnHandoff = YES;
  const int ends = _owner.ends;
  [_router exit:_info];
  Check(_router.claimed && _router.operation == NSDragOperationNone && !_owner.continuation &&
            _owner.ends == ends + 1,
        "reentrant owner loss cancels accepted handoff without fallback");
}

- (void)testAnUnacceptedExitIsTerminal {
  [self accept];
  [_router begin:_info];
  const int ends = _owner.ends;
  [_router exit:_info];
  Check(!_router.claimed && _owner.ends == ends + 1, "unaccepted exit remains terminal");
}

- (void)testMissingDraggingInfoCannotContinue {
  [self accept];
  _owner.handoff = YES;
  [_router begin:_info];
  [_router exit:nil];
  Check(!_router.claimed && !_owner.continuation, "missing dragging info cannot authorize continuation");
}

- (void)testAForeignOrMissingWindowIsRefused {
  [self accept];
  _drag.draggingDestinationWindow = nil;
  Check(![_router begin:_info], "foreign or missing original window refused");
}

@end
