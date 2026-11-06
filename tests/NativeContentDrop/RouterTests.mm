#import "content_drop_router.h"
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
static int count;
static void Check(bool b, const char* s) { ++count; if (!b) { fprintf(stderr,"%s\n",s); exit(1); } }
int main() { @autoreleasepool {
  [NSApplication sharedApplication];
  NSWindow* window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0,0,200,200) styleMask:NSWindowStyleMaskBorderless backing:NSBackingStoreBuffered defer:NO];
  DropFixture* owner = [[DropFixture alloc] initWithFrame:NSMakeRect(0,0,200,200)]; window.contentView = owner;
  NSView* view = [[NSView alloc] initWithFrame:owner.bounds]; [owner addSubview:view];
  DragFixture* drag = [DragFixture new]; drag.draggingDestinationWindow=window; drag.draggingPasteboard=[NSPasteboard pasteboardWithUniqueName]; drag.draggingSequenceNumber=7; drag.draggingSourceOperationMask=NSDragOperationCopy;
  [drag.draggingPasteboard setString:@"https://fixture.invalid" forType:NSPasteboardTypeURL];
  id<NSDraggingInfo> info=(id)drag;
  PCNativeContentDropRouter* router=[[PCNativeContentDropRouter alloc] initWithView:view];
  Check(![router begin:info] && !router.claimed, "declined input remains Chromium owned");
  owner.accepts=YES; owner.ready=YES; owner.succeeds=YES;
  Check([router begin:info] && router.claimed && router.operation==NSDragOperationCopy,"claim original native gesture");
  Check([router update:info]==NSDragOperationCopy && owner.updates==1,"update actual receiver");
  Check([router prepare:info] && [router perform:info] && owner.performs==1 && !router.claimed,"single native commit and cleanup");
  Check(![router perform:info] && owner.performs==1,"no repeated commit");
  [router begin:info]; int ends=owner.ends;
  [drag.draggingPasteboard clearContents];
  Check([router update:info]==NSDragOperationNone && router.claimed,"expired pasteboard never falls through to renderer");
  Check(owner.ends==ends+1 && ![router perform:info] && owner.performs==1,"expired payload cancels original preview without commit");
  [router begin:info]; ends=owner.ends; drag.draggingSequenceNumber++;
  Check(![router prepare:info] && router.claimed && owner.ends==ends+1,"different gesture invalidates original lease"); [router end];
  [router begin:info]; [view removeFromSuperview]; ends=owner.ends;
  Check([router update:info]==NSDragOperationNone && owner.ends==ends+1,"reparent cancels recipient");
  Check(router.claimed && ![router perform:info],"reparent cannot resume webpage fallback or drop");
  [owner addSubview:view]; [router begin:info]; owner.ready=NO;
  Check(![router perform:info] && owner.performs==1 && !router.claimed,"prepare refusal reports failure");
  owner.ready=YES; owner.succeeds=NO; [router begin:info];
  Check(![router perform:info] && owner.performs==2 && !router.claimed,"real commit failure preserved");
  drag.draggingSourceOperationMask=NSDragOperationMove; [router begin:info];
  Check(router.operation==NSDragOperationNone && [router update:info]==NSDragOperationNone,"honor source operation mask"); Check(![router prepare:info] && ![router perform:info], "incompatible operation cannot commit"); [router end];
  drag.draggingSourceOperationMask=NSDragOperationCopy;
  owner.accepts=YES; owner.succeeds=YES; owner.handoff=YES;
  [router begin:info]; ends=owner.ends; [router exit:info];
  Check(router.claimed && owner.continuation==router && owner.ends==ends,"exit retains only same accepted native router");
  Check([owner.continuation update:info]==NSDragOperationCopy,"ancestor continuation uses original lease");
  drag.draggingSequenceNumber++;
  Check(![owner.continuation prepare:info] && owner.ends==ends+1 && !owner.continuation,"handoff cannot accept another native sequence");
  [router begin:info]; [router exit:info]; ends=owner.ends; [router end];
  Check(owner.ends==ends+1 && !owner.continuation && !router.claimed,"original terminal callback retires ancestor continuation");
  [router begin:info]; owner.detachOnHandoff=YES; ends=owner.ends; [router exit:info];
  Check(router.claimed && router.operation==NSDragOperationNone && !owner.continuation && owner.ends==ends+1,"reentrant owner loss cancels accepted handoff without fallback");
  [owner addSubview:view]; owner.detachOnHandoff=NO; owner.handoff=NO;
  [router begin:info]; ends=owner.ends; [router exit:info];
  Check(!router.claimed && owner.ends==ends+1,"unaccepted exit remains terminal");
  owner.handoff=YES; [router begin:info]; [router exit:nil];
  Check(!router.claimed && !owner.continuation,"missing dragging info cannot authorize continuation");
  drag.draggingDestinationWindow=nil;
  Check(![router begin:info],"foreign or missing original window refused");
  [drag.draggingPasteboard releaseGlobally];
  printf("Native content drop router: %d checks passed\n", count);
} return 0; }
