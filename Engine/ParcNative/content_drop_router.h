// Source-owned native content drag routing. No page data or URL interpretation.
#pragma once
#import <AppKit/AppKit.h>
NS_ASSUME_NONNULL_BEGIN
@protocol PCNativeContentDropRouting;
NS_SWIFT_UI_ACTOR
@protocol PCNativeContentDropDestination <NSObject>
// Returning no operation declines this drag; Chromium retains its normal route.
- (NSDragOperation)contentView:(NSView *)view beginDrop:(id<NSDraggingInfo>)info;
- (NSDragOperation)contentView:(NSView *)view updateDrop:(id<NSDraggingInfo>)info;
- (BOOL)contentView:(NSView *)view prepareDrop:(id<NSDraggingInfo>)info;
- (BOOL)contentView:(NSView *)view performDrop:(id<NSDraggingInfo>)info;
- (void)contentViewDidEndDrop:(NSView *)view;
@optional
// The original accepted drag may continue inside this exact ancestor's reserved
// area. It retains this same router, never a substitute content owner or gesture.
- (BOOL)contentView:(NSView *)view handoffDrop:(id<NSDraggingInfo>)info
             router:(id<PCNativeContentDropRouting>)router;
@end

NS_SWIFT_UI_ACTOR
@protocol PCNativeContentDropRouting <NSObject>
@property(nonatomic, readonly) BOOL claimed;
@property(nonatomic, readonly) NSDragOperation operation;
- (BOOL)begin:(id<NSDraggingInfo>)info;
- (NSDragOperation)update:(id<NSDraggingInfo>)info;
- (BOOL)prepare:(id<NSDraggingInfo>)info;
- (BOOL)perform:(id<NSDraggingInfo>)info;
- (void)exit:(nullable id<NSDraggingInfo>)info;
- (void)end;
@end

// One native container owns this router. The implementation lives in ui/base;
// app consumers acquire the protocol through the public engine factory.
// A claimed gesture never falls through after its original ownership expires.
__attribute__((visibility("default")))
@interface PCNativeContentDropRouter : NSObject <PCNativeContentDropRouting>
- (instancetype)initWithView:(NSView *)view;
@end
NS_ASSUME_NONNULL_END
