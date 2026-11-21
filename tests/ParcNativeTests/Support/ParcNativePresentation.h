#pragma once

#ifdef __OBJC__
#define PARC_NATIVE_OFFSCREEN 1
#import "ParcNativeScheduling.h"
#import <AppKit/AppKit.h>
#import <SecurityInterface/SFCertificatePanel.h>

@interface NSWindow (ParcNativePresentation)
@property(readonly) NSWindow* parcAttachedSheet;
@property(readonly) NSWindow* parcSheetParent;
@property(readonly) NSWindow* parcParentWindow;
@property(readonly) NSArray<NSWindow*>* parcChildWindows;
- (void)parcBeginSheet:(NSWindow*)sheet completionHandler:(void (^)(NSModalResponse))completion;
- (void)parcEndSheet:(NSWindow*)sheet;
- (void)parcEndSheet:(NSWindow*)sheet returnCode:(NSModalResponse)code;
- (void)parcAddChildWindow:(NSWindow*)child ordered:(NSWindowOrderingMode)place;
- (void)parcRemoveChildWindow:(NSWindow*)child;
- (void)parcOrderFront:(id)sender;
- (void)parcMakeKeyAndOrderFront:(id)sender;
- (void)parcMakeKeyWindow;
- (void)parcOrderOut:(id)sender;
@end

@interface NSApplication (ParcNativePresentation)
- (void)parcEndSheet:(NSWindow*)sheet;
@end

@interface SFCertificatePanel (ParcNativePresentation)
- (void)parcBeginSheetForWindow:(NSWindow*)window modalDelegate:(id)delegate didEndSelector:(SEL)end
                    contextInfo:(void*)context certificates:(NSArray*)certificates showGroup:(BOOL)group;
@end

@interface ParcNativePopoverWindow : NSWindow
@property(weak) NSPopover* popover;
@property(weak) NSView* anchorView;
@property NSRect anchorRect;
@property NSRectEdge anchorEdge;
@end

@interface ParcNativePopover : NSPopover
@end

#define attachedSheet parcAttachedSheet
#define sheetParent parcSheetParent
#define parentWindow parcParentWindow
#define childWindows parcChildWindows
#define beginSheet parcBeginSheet
#define endSheet parcEndSheet
#define addChildWindow parcAddChildWindow
#define removeChildWindow parcRemoveChildWindow
#define orderFront parcOrderFront
#define makeKeyAndOrderFront parcMakeKeyAndOrderFront
#define makeKeyWindow parcMakeKeyWindow
#define orderOut parcOrderOut
#define beginSheetForWindow parcBeginSheetForWindow
#define NSPopover ParcNativePopover
#endif
